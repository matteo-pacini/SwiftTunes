import Darwin
import Foundation
import Testing
import TunesContract
@testable import TunesEngine
import TunesRules

nonisolated enum RealServer {
    static var configured: Bool {
        let env = ProcessInfo.processInfo.environment
        return ["TUNES_REAL_ACE_SERVER", "TUNES_REAL_MODELS", "TUNES_REAL_OUT"].allSatisfy { env[$0]?.isEmpty == false }
    }
}

/// One tune composed end to end by the engine with a real ace-server and the
/// real weights. Off unless TUNES_REAL_ACE_SERVER (the server binary),
/// TUNES_REAL_MODELS (a folder holding the four pinned files) and
/// TUNES_REAL_OUT (an empty folder for the run's files) are set. Nothing is
/// played: the player is the silent fake.
@Suite(.serialized, .enabled(if: RealServer.configured), .timeLimit(.minutes(20)))
struct RealServerTests {
    static let env = ProcessInfo.processInfo.environment

    static func lifetimeMax(_ pid: Int32) -> Int64? {
        var info = rusage_info_v4()
        let rc = withUnsafeMutablePointer(to: &info) { p in
            p.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        return rc == 0 ? Int64(info.ri_lifetime_max_phys_footprint) : nil
    }

    @Test func oneTuneEndToEnd() async throws {
        let server = URL(filePath: Self.env["TUNES_REAL_ACE_SERVER"]!)
        let models = URL(filePath: Self.env["TUNES_REAL_MODELS"]!, directoryHint: .isDirectory)
        let out = URL(filePath: Self.env["TUNES_REAL_OUT"]!, directoryHint: .isDirectory)
        let lifeline = try #require(LifelineTests.lifeline)
        let package = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let paths = EnginePaths(
            support: out.appending(path: "support", directoryHint: .isDirectory), models: models,
            caches: out.appending(path: "caches", directoryHint: .isDirectory),
            music: out.appending(path: "Music/Tunes", directoryHint: .isDirectory)
        )
        let player = FakePlayer()
        let tap = TapLauncher(LivePieces.launcher(lifeline: lifeline, server: server))
        let engine = Engine(EngineEnvironment(
            paths: paths, aceServer: server, defaultGenres: package.appending(path: "Resources/genres.json"),
            pins: package.appending(path: "Config/pins.json"), clock: LivePieces.clock(), random: SystemRandomNumberGenerator(),
            player: player, launcher: tap, holds: LivePieces.holds(), probe: LivePieces.probe()
        ))
        #expect(engine.snapshot.setup == .ready)

        var log: [String] = []
        var peak: Int64 = 0
        var waiters: [(check: (Snapshot) -> Bool, cont: CheckedContinuation<Void, Never>)] = []
        let t0 = Date()
        var lastState: ModelState?
        let token = engine.observe { s in
            if let pid = engine.server?.process?.serverPID, let m = Self.lifetimeMax(pid) { peak = max(peak, m) }
            if s.model.state != lastState {
                lastState = s.model.state
                log.append(String(format: "%7.2f s  %@%@", Date().timeIntervalSince(t0), s.model.state.rawValue,
                                  s.model.detail.map { " (\($0))" } ?? ""))
            }
            let ready = waiters.filter { $0.check(s) }
            waiters.removeAll { $0.check(s) }
            ready.forEach { $0.cont.resume() }
        }
        func until(_ check: @escaping (Snapshot) -> Bool) async {
            if check(engine.snapshot) { return }
            await withCheckedContinuation { waiters.append((check, $0)) }
        }

        engine.send(.selectGenre(id: "lofi"))
        engine.send(.setComposer(on: true))
        await until { $0.tune != nil || $0.ready > 0 || $0.model.state == .failed || $0.model.state == .noDevice || $0.model.state.rawValue.hasPrefix("held") }
        let done = engine.snapshot
        // The server keeps composing the second tune; its lifetime maximum
        // covers both stages of the first.
        if let pid = engine.server?.process?.serverPID, let m = Self.lifetimeMax(pid) { peak = max(peak, m) }
        let elapsed = Date().timeIntervalSince(t0)
        await engine.shutdown()
        token.cancel()

        let tunes = Files.list(paths.music.appending(path: "Lo-fi")).filter(TuneFiles.isTune)
        var report = log
        report.append("first tune after \(String(format: "%.1f", elapsed)) s")
        report.append("timings: writing \(done.expect.map { "\($0.writingS)" } ?? "-") s, rendering \(done.expect.map { "\($0.renderingS)" } ?? "-") s")
        report.append("device: \(done.model.device)")
        report.append("server peak footprint: \(peak) bytes (\(String(format: "%.2f", Double(peak) / 1_073_741_824)) GiB)")
        report.append("tune: \(done.tune?.name ?? "-") \(done.tune?.bpm.map(String.init) ?? "-") BPM \(done.tune?.key ?? "-") length \(done.tune?.length.map { "\($0)" } ?? "-") s")
        report.append("files: \(tunes)")
        report.append("server exits: \(tap.exits)")
        try Data((report.joined(separator: "\n") + "\n").utf8).write(to: out.appending(path: "report.txt"))
        print(report.joined(separator: "\n"))

        #expect(done.model.state != .failed && done.model.state != .noDevice)
        #expect(tunes.count >= 1)
        #expect(done.tune?.wave.count == 78)
    }
}
