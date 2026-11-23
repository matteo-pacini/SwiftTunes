import Darwin
import Foundation
import Testing
import TunesContract
@testable import TunesEngine
import TunesFakes
import TunesRules

/// Passes a launcher's lines and exits through, and lets a test wait for them.
final class TapLauncher: ServerLauncher {
    let inner: any ServerLauncher
    var lines: [String] = []
    var exits: [Int32] = []
    private var waiters: [(check: () -> Bool, cont: CheckedContinuation<Void, Never>)] = []

    init(_ inner: any ServerLauncher) { self.inner = inner }

    func launch(
        arguments: [String], onLine: @escaping @MainActor (String) -> Void, onExit: @escaping @MainActor (Int32) -> Void
    ) throws -> any ServerProcess {
        try inner.launch(
            arguments: arguments,
            onLine: { [weak self] line in
                self?.lines.append(line)
                onLine(line)
                self?.wake()
            },
            onExit: { [weak self] status in
                self?.exits.append(status)
                onExit(status)
                self?.wake()
            }
        )
    }

    /// Returns once `check` holds, checked after every line and exit.
    func until(_ check: @escaping () -> Bool) async {
        if check() { return }
        await withCheckedContinuation { waiters.append((check, $0)) }
    }

    private func wake() {
        let ready = waiters.filter { $0.check() }
        waiters.removeAll { $0.check() }
        ready.forEach { $0.cont.resume() }
    }
}

@Suite(.serialized, .timeLimit(.minutes(1))) struct LifelineTests {
    /// The tunes-lifeline this package built: beside the test bundle, or in
    /// the package's own build folder.
    static var lifeline: URL? {
        var candidates: [URL] = []
        if let b = Bundle.allBundles.first(where: { $0.bundlePath.hasSuffix(".xctest") }) {
            candidates.append(b.bundleURL.deletingLastPathComponent().appending(path: "tunes-lifeline"))
        }
        let package = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        candidates.append(package.appending(path: ".build/debug/tunes-lifeline"))
        candidates.append(package.appending(path: ".build/release/tunes-lifeline"))
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// A stand-in server: records its pid and a child's, prints the lines the
    /// engine waits for, and waits; the child is a grandchild of the shim.
    static func standIn(in dir: URL) throws -> URL {
        let url = dir.appending(path: "stand-in-server")
        let script = """
        #!/bin/sh
        sleep 1000 &
        echo "$$ $! $(ps -o nice= -p $$)" > "$2/pids"
        echo "tunes-lifeline: started 1" >&2
        echo "ggml_metal_device_init: GPU name:   MTL0 (Stand-in)" >&2
        echo "[Server] Listening on 127.0.0.1:0" >&2
        wait

        """
        try Data(script.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    static func alive(_ pid: Int32) -> Bool { kill(pid, 0) == 0 }

    func startedServer() async throws -> (Rig, TapLauncher, [Int32]) {
        let lifeline = try #require(Self.lifeline, "tunes-lifeline is not built beside the tests")
        let rig = try await Rig()
        let script = try Self.standIn(in: rig.root)
        let tap = TapLauncher(LivePieces.launcher(lifeline: lifeline, server: script))
        rig.realLauncher = tap
        rig.make()
        await rig.send(.selectGenre(id: "jazz"))
        rig.engine.send(.setComposer(on: true))
        await tap.until { tap.lines.contains { $0.hasPrefix("[Server] Listening") } }
        #expect(tap.lines.first?.hasPrefix("tunes-lifeline: started ") == true)
        let text = try #require(Files.read(rig.paths.models.appending(path: "pids")))
        let fields = text.split(whereSeparator: \.isWhitespace).compactMap { Int32($0) }
        let pids = Array(fields.prefix(2))
        #expect(pids.count == 2 && pids.allSatisfy(Self.alive))
        #expect(fields.last == 10, "the server's nice")
        #expect(rig.engine.server?.process?.serverPID == pids.first)
        return (rig, tap, pids)
    }

    @Test func shutdownLeavesNoChild() async throws {
        let (rig, tap, pids) = try await startedServer()
        await rig.engine.shutdown()
        #expect(tap.exits.count == 1)
        #expect(pids.allSatisfy { !Self.alive($0) })
        await rig.close()
    }

    @Test func composerOffStopsTheRealServer() async throws {
        let (rig, tap, pids) = try await startedServer()
        rig.engine.send(.setComposer(on: false))
        await tap.until { tap.exits.count == 1 }
        #expect(pids.allSatisfy { !Self.alive($0) })
        #expect(rig.engine.server == nil && rig.snap.model.state == .unloaded)
        await rig.close()
    }

    @Test func aServerThatCannotBeRunIsAFailure() async throws {
        let lifeline = try #require(Self.lifeline)
        let rig = try await Rig()
        let tap = TapLauncher(LivePieces.launcher(lifeline: lifeline, server: rig.root.appending(path: "missing-server")))
        rig.realLauncher = tap
        rig.make()
        await rig.send(.selectGenre(id: "jazz"))
        rig.engine.send(.setComposer(on: true))
        await tap.until { !tap.exits.isEmpty }
        await rig.settle()
        #expect(tap.exits == [127])
        #expect(rig.snap.model.state == .failed)
        #expect(rig.snap.model.detail?.hasPrefix("the model server exited (status 127): tunes-lifeline: failed to run ") == true)
        await rig.close()
    }

    /// A stand-in that, like the real server mid-job, ignores SIGTERM.
    static func deafStandIn(in dir: URL) throws -> URL {
        let url = dir.appending(path: "deaf-server")
        let script = """
        #!/bin/sh
        trap 'echo term >> "$2/term"' TERM
        trap '' HUP
        sleep 1000 &
        echo "$$ $!" > "$2/pids"
        echo "ggml_metal_device_init: GPU name:   MTL0 (Stand-in)" >&2
        echo "[Server] Listening on 127.0.0.1:0" >&2
        while :; do wait; done

        """
        try Data(script.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    @Test func aStopMidJobKillsAServerThatIgnoresTerm() async throws {
        let lifeline = try #require(Self.lifeline)
        let rig = try await Rig()
        let tap = TapLauncher(LivePieces.launcher(lifeline: lifeline, server: try Self.deafStandIn(in: rig.root)))
        rig.realLauncher = tap
        rig.make()
        // The stand-in speaks no HTTP; the fake server answers for it, and
        // never lets the cancelled job end.
        await rig.ace.set(up: true)
        await rig.ace.set(runningPolls: 100)
        await rig.ace.set(cancelPolls: 100_000)
        await rig.send(.selectGenre(id: "jazz"))
        rig.engine.send(.setComposer(on: true))
        await tap.until { tap.lines.contains { $0.hasPrefix("[Server] Listening") } }
        #expect(await rig.run { rig.snap.model.state == .writing })
        let text = try #require(Files.read(rig.paths.models.appending(path: "pids")))
        let pids = text.split(whereSeparator: \.isWhitespace).compactMap { Int32($0) }
        #expect(pids.count == 2 && pids.allSatisfy(Self.alive))

        let port = rig.aceHTTP.port
        let t = rig.clock.now
        rig.engine.send(.setComposer(on: false))
        #expect(await rig.run { rig.engine.timers["drain:\(port)"] == nil })
        await tap.until { !tap.exits.isEmpty }
        #expect(abs(rig.clock.now - t - 1) < 1e-6, "the wait is one second")
        // Killed by the engine, not ended by the shim: the shim's way starts
        // with a SIGTERM, which the stand-in would have noted.
        #expect(!Files.exists(rig.paths.models.appending(path: "term")))
        #expect(tap.exits == [137])
        #expect(pids.allSatisfy { !Self.alive($0) })
        #expect(await rig.ace.cancelled.count == 1)
        await rig.close()
    }
}
