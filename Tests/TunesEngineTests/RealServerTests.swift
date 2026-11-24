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
        // Nothing plays, so the new tune waits in the queue.
        let made = engine.ready.first ?? engine.current
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
        report.append("tune: \(made?.name ?? "-"), \(made?.bpm.map(String.init) ?? "-") BPM, \(made?.key ?? "-"), \(made?.length.map { "\($0)" } ?? "-") s, \(made?.wave.count ?? 0) wave bars")
        report.append("shutdown took \(String(format: "%.1f", Date().timeIntervalSince(t0) - elapsed)) s")
        report.append("files: \(tunes)")
        report.append("server exits: \(tap.exits)")
        try Data((report.joined(separator: "\n") + "\n").utf8).write(to: out.appending(path: "report.txt"))
        print(report.joined(separator: "\n"))

        #expect(done.model.state != .failed && done.model.state != .noDevice)
        #expect(tunes.count >= 1)
        #expect(made?.wave.count == 78 && made?.length != nil)
    }
}

/// Words through the real server, plans only: the engine's own job and
/// request for a sung genre, then for the user's words. No /synth is sent and
/// nothing is heard. Off unless TUNES_REAL_PLANS is set besides the three
/// variables above; at most three /lm requests.
@Suite(.serialized, .enabled(if: RealServer.configured && ProcessInfo.processInfo.environment["TUNES_REAL_PLANS"] != nil),
       .timeLimit(.minutes(10)))
struct RealPlansTests {
    static let caption = "lo-fi hip hop song, dusty vinyl crackle, warm detuned electric piano, soft boom bap drums, mellow bass, a soft female voice singing a simple melodic hook, sung verses and chorus"
    static let words = """
    [Verse]
    paper boats along the gutter
    sailing where the streetlights end
    [Chorus]
    slow down, slow down
    the evening is a friend
    """

    /// The answer to a job once it is done, polling as the engine does.
    static func plan(_ client: ServerClient, _ body: JSONValue) async throws -> JSONValue {
        let id = try ServerClient.jobID(try await client.json("POST", "/lm", body: body))
        while true {
            let status = try await client.json("GET", ServerClient.jobPath(id))["status"]
            if status != .string("running") {
                #expect(status == .string("done"))
                break
            }
            try await Task.sleep(for: .seconds(Rules.poll))
        }
        let data = try await client.call("GET", ServerClient.jobPath(id, "&result=1"), timeout: 60)
        guard case .array(let list) = try JSONValue.parse(String(decoding: data, as: UTF8.self)), let first = list.first else {
            throw ServerClient.Failure(description: "no plan")
        }
        return first
    }

    @Test func aSungPlanAndAnOwnWordsPlan() async throws {
        let env = ProcessInfo.processInfo.environment
        let server = URL(filePath: env["TUNES_REAL_ACE_SERVER"]!)
        let out = URL(filePath: env["TUNES_REAL_OUT"]!, directoryHint: .isDirectory)
        let lifeline = try #require(LifelineTests.lifeline)
        let package = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let genres = out.appending(path: "genres-sung.json")
        try Data("""
        {"genres": [{"id": "lofi", "name": "Lo-fi", "caption": "\(Self.caption)", "turns": [], "bpm": [70, 92], "sung": true}]}
        """.utf8).write(to: genres)
        let paths = EnginePaths(
            support: out.appending(path: "support", directoryHint: .isDirectory),
            models: URL(filePath: env["TUNES_REAL_MODELS"]!, directoryHint: .isDirectory),
            caches: out.appending(path: "caches", directoryHint: .isDirectory),
            music: out.appending(path: "Music/Tunes", directoryHint: .isDirectory)
        )
        let engine = Engine(EngineEnvironment(
            paths: paths, aceServer: server, defaultGenres: genres, pins: package.appending(path: "Config/pins.json"),
            clock: LivePieces.clock(), random: SystemRandomNumberGenerator(), player: FakePlayer(),
            launcher: LivePieces.launcher(lifeline: lifeline, server: server), holds: LivePieces.holds(), probe: LivePieces.probe()
        ))
        engine.send(.selectGenre(id: "lofi"))
        let g = try #require(engine.genre)
        #expect(g.sung)

        // The server, started as the engine starts it.
        let port = LoopbackPort.free()
        let tap = TapLauncher(LivePieces.launcher(lifeline: lifeline, server: server))
        let process = try tap.launch(
            arguments: ["--models", paths.models.path, "--device", ServerLog.device, "--host", "127.0.0.1", "--port", String(port)],
            onLine: { _ in }, onExit: { _ in }
        )
        await tap.until { tap.lines.contains { ServerLog.isListening($0) } }
        let client = ServerClient(host: "127.0.0.1", port: port)
        var log: [String] = []
        var calls = 0

        // A sung plan: written again once if its words are too thin.
        var sung: JSONValue = .null
        for _ in 0..<2 {
            let job = engine.makeJob(g, own: nil)
            let body = engine.lmBody(job)
            #expect(body["lyrics"] == .string("") && body["vocal_language"] == .string("en"))
            #expect(job.caption == Self.caption && !job.caption.contains("instrumental"))
            calls += 1
            let t = Date()
            sung = try await Self.plan(client, body)
            var words = ""
            if case .string(let w)? = sung["lyrics"] { words = w }
            log.append("sung plan \(calls): \(String(format: "%.1f", Date().timeIntervalSince(t))) s, \(WordsRules.sungLines(words).count) sung lines, thin \(WordsRules.tooThin(words)), language \(sung["vocal_language"].map { $0.dumps() } ?? "-")")
            log.append(words)
            if !WordsRules.tooThin(words) { break }
        }

        // The user's words, sent as given.
        let own = engine.makeJob(g, own: OwnWords(words: Self.words, name: "Paper Boats", genreID: g.id))
        let body = engine.lmBody(own)
        #expect(body["lyrics"] == .string(Self.words) && body["vocal_language"] == .string("en"))
        calls += 1
        let t = Date()
        let plan = try await Self.plan(client, body)
        var back = ""
        if case .string(let w)? = plan["lyrics"] { back = w }
        log.append("own words plan: \(String(format: "%.1f", Date().timeIntervalSince(t))) s, words back equal words sent: \(back == Self.words)")
        log.append(back)
        #expect(back == Self.words)
        #expect(calls <= 3)

        process.stop()
        await process.waitForExit()
        log.append("server exits: \(tap.exits), /lm calls: \(calls)")
        try Data((log.joined(separator: "\n") + "\n").utf8).write(to: out.appending(path: "plans.txt"))
        print(log.joined(separator: "\n"))
        await engine.shutdown()
    }
}
