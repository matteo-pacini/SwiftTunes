import Foundation
import Testing
import TunesContract
@testable import TunesEngine
import TunesFakes
import TunesRules

/// Faults found by review, each pinned by the input that showed it.
@Suite(.serialized, .timeLimit(.minutes(1))) struct FaultTests {
    func keptRig(_ count: Int, repeat mode: RepeatMode = .all) async throws -> (Rig, [String]) {
        let rig = try await Rig()
        for d in 1...count { try rig.keptTune("Jazz", day: d) }
        rig.make()
        await rig.send(.setShuffle(on: false))
        await rig.send(.setRepeat(mode))
        await rig.send(.selectGenre(id: "jazz"))
        return (rig, rig.tunes("Jazz"))
    }

    @Test func repeatOneRepublishesPositionZeroAtEachLoop() async throws {
        let (rig, _) = try await keptRig(2, repeat: .one)
        rig.player.position = 177
        rig.clock.now += 177
        let before = rig.snapshots.count
        rig.player.finish()
        await rig.settle()
        #expect(rig.snapshots.count == before + 1)
        #expect(rig.snap.pos == 0 && rig.snap.posAt == rig.clock.now)
        #expect(rig.snap.player == .playing)
        await rig.close()
    }

    @Test func memoryFigureFollowsTheServerWhileAStageRuns() async throws {
        let rig = try await Rig()
        await rig.ace.set(runningPolls: 100)
        await rig.send(.selectGenre(id: "jazz"))
        rig.probe.bytes = 100_000_000
        await rig.send(.setComposer(on: true))
        #expect(await rig.run { rig.snap.model.state == .writing })
        #expect(rig.snap.model.ramUsedBytes == 100_000_000)
        // A move under 0.1 GiB publishes nothing.
        rig.probe.bytes = 150_000_000
        let count = rig.snapshots.count
        for _ in 0..<4 {
            _ = rig.clock.fireNext()
            await rig.settle()
        }
        #expect(rig.snapshots.count == count)
        // The model loads: the next poll shows it.
        rig.probe.bytes = 7_400_000_000
        #expect(await rig.run(until: { rig.snap.model.ramUsedBytes == 7_400_000_000 }, steps: 3))
        #expect(rig.snap.model.state == .writing)
        await rig.close()
    }

    @Test func aRenameThatChangesOnlyCase() async throws {
        let rig = try await Rig()
        try rig.keptTune("Lo-fi", day: 1)
        rig.make()
        let lofi = try await rig.engine.genre(id: "lofi").get()
        var f = lofi
        f.name = "Lo-Fi"
        let saved = await rig.engine.saveGenre(id: "lofi", fields: f, base: lofi)
        #expect(saved == .success(GenreSaved(id: "lofi", renamed: Renamed(from: "Lo-fi", to: "Lo-Fi"))))
        let folders = Files.list(rig.paths.music)
        #expect(folders.contains("Lo-Fi") && !folders.contains("Lo-fi"))
        #expect(rig.tunes("Lo-Fi").count == 1)
        await rig.close()
    }

    @Test func shutdownCancelsWorkInFlight() async throws {
        let rig = try await Rig()
        await rig.ace.set(holdLM: true)
        await rig.send(.selectGenre(id: "jazz"))
        rig.engine.send(.setComposer(on: true))
        _ = await rig.launcher.deliver()
        await rig.ace.untilLMHeld()
        #expect(rig.engine.inFlight > 0)
        // Shut down without waiting for the engine to be quiet: the held
        // request would keep it busy until its own timeout.
        var done = false
        let engine = rig.engine!
        let task = Task {
            await engine.shutdown()
            done = true
        }
        for _ in 0..<10_000 where !done {
            await Task.yield()
            _ = await rig.launcher.deliver()
            _ = rig.clock.fireNext()
        }
        #expect(done, "shutdown returned")
        if done { await task.value }
        #expect(rig.engine.inFlight == 0)
        await rig.ace.releaseLM()
        await rig.close()
    }

    @Test func aCompletePartIsFinishedWithNoRequest() async throws {
        let rig = try await Rig(ready: false)
        try FileManager.default.createDirectory(at: rig.paths.models, withIntermediateDirectories: true)
        try rig.modelFiles["fake-lm.gguf"]!.write(to: rig.paths.models.appending(path: "fake-lm.gguf.part"))
        rig.make()
        await rig.send(.download)
        #expect(await rig.run { rig.snap.setup == .ready })
        #expect(await !rig.host.requests.contains { $0.hasSuffix("/fake-lm.gguf") })
        await rig.close()
    }

    @Test func aCompletePartWithTheWrongBytesIsRefusedAndRemoved() async throws {
        let rig = try await Rig(ready: false)
        try FileManager.default.createDirectory(at: rig.paths.models, withIntermediateDirectories: true)
        var bad = rig.modelFiles["fake-lm.gguf"]!
        bad[0] ^= 0xFF
        let part = rig.paths.models.appending(path: "fake-lm.gguf.part")
        try bad.write(to: part)
        rig.make()
        await rig.send(.download)
        #expect(await rig.run { rig.snap.setup == .failed })
        #expect(rig.snap.download?.error == "fake-lm.gguf: checksum mismatch")
        #expect(!Files.exists(part))
        await rig.close()
    }

    @Test func noIdleStateWithAServerAndNoJobWhileWorking() async throws {
        let rig = try await Rig()
        await rig.send(.selectGenre(id: "jazz"))
        await rig.send(.setComposer(on: true))
        #expect(await rig.run { rig.snap.ready == 2 && rig.snap.model.state == .idle })
        for s in rig.snapshots {
            if s.model.state == .writing || s.model.state == .rendering {
                #expect(s.job != nil, "\(s.model.state) with no job")
            }
            if s.model.state == .idle {
                #expect(s.model.ramUsedBytes == nil, "idle with a server process")
            }
        }
        await rig.close()
    }

    @Test func scrappingTheJobGoesStraightToTheNextOne() async throws {
        let rig = try await Rig()
        await rig.ace.set(runningPolls: 100)
        await rig.send(.selectGenre(id: "jazz"))
        await rig.send(.setComposer(on: true))
        #expect(await rig.run { rig.snap.model.state == .writing })
        let n = rig.snapshots.count
        await rig.send(.scrapJob)
        #expect(rig.snapshots.dropFirst(n).allSatisfy { $0.model.state == .writing && $0.job != nil })
        await rig.close()
    }

    @Test func undoNeverOverwritesAFileThatAppeared() async throws {
        let (rig, k) = try await keptRig(3)
        let name = TuneFiles.stem(k[0])
        await rig.send(.scrapPlaying(name: name))
        let path = rig.genreDir("Jazz").appending(path: k[0])
        try Data("someone else's".utf8).write(to: path)
        await rig.send(.undo)
        #expect(rig.snap.error == "could not bring \(name) back: File exists")
        #expect(FileManager.default.contents(atPath: path.path) == Data("someone else's".utf8))
        #expect(rig.snap.undo != nil)
        await rig.close()
    }

    @Test func positionIsNotSampledWhileATuneLoads() async throws {
        let (rig, _) = try await keptRig(3)
        rig.player.position = 42
        let t = rig.clock.now
        await rig.send(.refresh)
        #expect(rig.snap.pos == 42 && rig.snap.posAt == t)
        rig.clock.now += 5
        let q = rig.snap.queue[1]
        rig.engine.send(.playQueued(index: 1, name: q.name))
        // The old item plays on until the new one starts; its position is
        // not read: the chosen tune shows from its start.
        rig.player.position = 47
        await rig.engine.quiet()
        #expect(rig.snap.tune?.file == q.file && rig.snap.pos == 0 && rig.snap.posAt == rig.clock.now)
        _ = t
        await rig.settle()
        #expect(rig.snap.tune?.file == q.file && rig.snap.pos == 0 && rig.snap.posAt == rig.clock.now)
        await rig.close()
    }

    @Test func jobIDsThatNeedEscaping() async throws {
        let rig = try await Rig()
        await rig.ace.set(idPrefix: "job #7&x=1 ")
        await rig.send(.selectGenre(id: "jazz"))
        await rig.send(.setComposer(on: true))
        #expect(await rig.run { rig.snap.tune != nil })
        await rig.close()
    }
}
