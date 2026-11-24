import Foundation
import Testing
import TunesContract
@testable import TunesEngine
import TunesFakes
import TunesRules

/// Removing the music model: only the pinned files and their parts go.
@Suite(.serialized, .timeLimit(.minutes(1))) struct ModelRemovalTests {
    func onDisk(_ rig: Rig) -> [String] {
        Files.list(rig.paths.models).sorted()
    }

    var total: (Rig) -> Int64 { { Int64($0.modelFiles.values.reduce(0) { $0 + $1.count }) } }

    @Test func whileIdle() async throws {
        let rig = try await Rig()
        #expect(rig.snap.setup == .ready && rig.snap.need.onDiskBytes == total(rig))
        await rig.send(.removeModel)
        #expect(onDisk(rig).isEmpty)
        #expect(rig.snap.setup == .missing && rig.snap.need.onDiskBytes == 0 && rig.snap.need.downloadBytes == total(rig))
        #expect(rig.snap.error == nil)
        await rig.close()
    }

    @Test func nothingOnDiskIsIgnored() async throws {
        let rig = try await Rig(ready: false)
        let n = rig.snapshots.count
        await rig.send(.removeModel)
        #expect(rig.snapshots.count == n)
        await rig.close()
    }

    @Test func whileComposing() async throws {
        let rig = try await Rig()
        await rig.ace.set(runningPolls: 100)
        await rig.send(.selectGenre(id: "jazz"))
        await rig.send(.setComposer(on: true))
        #expect(await rig.run { rig.snap.model.state == .writing })
        await rig.send(.removeModel)
        #expect(await rig.run { rig.launcher.running == 0 })
        #expect(!rig.snap.composing && rig.snap.job == nil && rig.snap.model.state == .unloaded)
        #expect(await rig.ace.cancelled.count == 1)
        #expect(onDisk(rig).isEmpty && rig.snap.setup == .missing)
        // The switch cannot come back on without the model.
        await rig.send(.setComposer(on: true))
        #expect(!rig.snap.composing)
        await rig.close()
    }

    @Test func whileDownloading() async throws {
        let rig = try await Rig(ready: false)
        await rig.host.set(holdAfter: 500)
        rig.engine.send(.download)
        await rig.host.untilHeld()
        rig.engine.send(.removeModel)
        await rig.host.release()
        await rig.settle()
        #expect(rig.snap.download == nil && rig.snap.setup == .missing)
        #expect(onDisk(rig).isEmpty && rig.snap.need.onDiskBytes == 0)
        await rig.close()
    }

    @Test func otherFilesInTheFolderStay() async throws {
        let rig = try await Rig()
        try Data("mine".utf8).write(to: rig.paths.models.appending(path: "notes.txt"))
        try Data("mine".utf8).write(to: rig.paths.models.appending(path: "another-model.gguf"))
        try Data("part".utf8).write(to: rig.paths.models.appending(path: "another-model.gguf.part"))
        await rig.send(.removeModel)
        #expect(onDisk(rig) == ["another-model.gguf", "another-model.gguf.part", "notes.txt"])
        #expect(rig.snap.need.onDiskBytes == 0)
        await rig.close()
    }

    @Test func aPartIsRemovedToo() async throws {
        let rig = try await Rig(ready: false)
        try FileManager.default.createDirectory(at: rig.paths.models, withIntermediateDirectories: true)
        try rig.modelFiles["fake-dit.gguf"]!.prefix(100).write(to: rig.paths.models.appending(path: "fake-dit.gguf.part"))
        rig.make()
        #expect(rig.snap.need.onDiskBytes == 100)
        await rig.send(.removeModel)
        #expect(onDisk(rig).isEmpty && rig.snap.need.onDiskBytes == 0)
        await rig.close()
    }

    @Test func aDeleteFailureIsSaid() async throws {
        let rig = try await Rig()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: rig.paths.models.path)
        await rig.send(.removeModel)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: rig.paths.models.path)
        #expect(rig.snap.error == "could not remove the music model: Permission denied")
        #expect(rig.snap.need.onDiskBytes == total(rig))
        // Tried again with the folder writable: done, and the sentence goes.
        await rig.send(.removeModel)
        #expect(rig.snap.error == nil && onDisk(rig).isEmpty)
        await rig.close()
    }

    @Test func aDownloadAfterRemoval() async throws {
        let rig = try await Rig()
        await rig.send(.removeModel)
        await rig.send(.download)
        #expect(await rig.run { rig.snap.setup == .ready })
        #expect(rig.snap.need.onDiskBytes == total(rig) && onDisk(rig).count == 4)
        // It grew with the download, part by part.
        let during = rig.snapshots.filter { $0.setup == .downloading }.map(\.need.onDiskBytes)
        #expect(during.contains { $0 > 0 && $0 < total(rig) } && during == during.sorted())
        await rig.close()
    }

    @Test func keptTunesPlayOnThroughIt() async throws {
        let rig = try await Rig()
        for d in 1...3 { try rig.keptTune("Jazz", day: d) }
        rig.make()
        await rig.send(.selectGenre(id: "jazz"))
        let playing = rig.snap.tune
        let calls = rig.player.calls
        await rig.send(.removeModel)
        #expect(rig.player.calls == calls)
        #expect(rig.snap.tune == playing && rig.snap.player == .playing)
        rig.player.finish()
        await rig.settle()
        #expect(rig.snap.tune != nil && rig.snap.tune?.file != playing?.file)
        await rig.close()
    }
}
