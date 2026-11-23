import AVFoundation
import Foundation
import Testing
import TunesContract
@testable import TunesEngine
import TunesFakes
import TunesRules

@Suite(.serialized, .timeLimit(.minutes(1))) struct RenameTests {
    struct Tags: Equatable {
        var title: String?
        var genre: String?
        var tempo: Int?
        var comment: String?
        var seconds: Double
        var frames: AVAudioFramePosition
    }

    static func tags(_ url: URL) async throws -> Tags {
        let asset = AVURLAsset(url: url)
        let items = try await asset.load(.metadata)
        func string(_ id: AVMetadataIdentifier) async throws -> String? {
            try await AVMetadataItem.metadataItems(from: items, filteredByIdentifier: id).first?.load(.stringValue)
        }
        let tempo = try await AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .iTunesMetadataBeatsPerMin).first?.load(.numberValue)
        return Tags(
            title: try await string(.iTunesMetadataSongName), genre: try await string(.iTunesMetadataUserGenre),
            tempo: tempo?.intValue, comment: try await string(.iTunesMetadataUserComment),
            seconds: try await asset.load(.duration).seconds, frames: try AVAudioFile(forReading: url).length
        )
    }

    /// Jazz picked with real kept tunes, shuffle off.
    func keptRig(_ titles: [String]) async throws -> Rig {
        let rig = try await Rig()
        for (i, t) in titles.enumerated() { try await rig.realKeptTune("Jazz", day: i + 1, title: t) }
        rig.make()
        await rig.send(.setShuffle(on: false))
        await rig.send(.selectGenre(id: "jazz"))
        return rig
    }

    @Test func aNewTuneKeepsItsAudioAndOtherTags() async throws {
        let rig = try await Rig()
        await rig.send(.selectGenre(id: "jazz"))
        await rig.send(.stop)
        await rig.send(.setComposer(on: true))
        #expect(await rig.run { rig.snap.ready == 2 })
        let tune = rig.snap.queue[0]
        let url = rig.genreDir("Jazz").appending(path: tune.file + ".m4a")
        let before = try await Self.tags(url)
        let bytes = try #require(Files.size(url))
        let pin = rig.genreDir("Jazz").appending(path: ".\(tune.file).m4a.pin")
        try Files.touch(pin)

        let n = rig.snapshots.count
        let r = await rig.engine.renameTune(TuneTarget(name: tune.name, index: 0), to: "  Night Walk ")
        #expect(r == .success("Night Walk"))
        await rig.settle()
        let after = try await Self.tags(url)
        #expect(after.title == "Night Walk" && before.title == tune.name)
        #expect(after.genre == before.genre && after.tempo == before.tempo && after.comment == before.comment)
        #expect(after.seconds == before.seconds && after.frames == before.frames)
        let newBytes = try #require(Files.size(url))
        #expect(abs(newBytes - bytes) < 4096, "\(bytes) → \(newBytes)")
        #expect(rig.tunes("Jazz").contains(tune.file + ".m4a") && Files.exists(pin))
        #expect(!Files.list(rig.genreDir("Jazz")).contains { $0.hasSuffix(".part") })
        #expect(rig.snap.queue[0].name == "Night Walk" && rig.snap.queue[0].file == tune.file)
        #expect(rig.snapshots.count == n + 1)
        // The wave cache follows the file, so a restart shows the new name.
        rig.make()
        await rig.send(.selectGenre(id: "jazz"))
        let all = [rig.snap.tune?.name] + rig.snap.queue.map(\.name)
        #expect(all.contains("Night Walk"))
        await rig.close()
    }

    @Test func thePlayingTuneIsRenamedWithoutInterruption() async throws {
        let rig = try await keptRig(["Old Lamp", "Blue Avenue", "Smoky Window"])
        let playing = try #require(rig.snap.tune)
        #expect(playing.name == "Old Lamp")
        let calls = rig.player.calls
        let r = await rig.engine.renameTune(TuneTarget(name: "Old Lamp", index: nil), to: "Lamp at Dawn")
        #expect(r == .success("Lamp at Dawn"))
        await rig.settle()
        #expect(rig.snap.tune?.name == "Lamp at Dawn" && rig.snap.tune?.file == playing.file)
        #expect(rig.snap.player == .playing && rig.player.calls == calls)
        // Commands carry the new name; the old one names nothing, the stem still does.
        await rig.send(.scrapPlaying(name: "Old Lamp"))
        #expect(rig.snap.tune?.file == playing.file)
        await rig.send(.scrapPlaying(name: "Lamp at Dawn"))
        #expect(rig.snap.undo?.name == "Lamp at Dawn")
        await rig.close()
    }

    @Test func aQueuedKeptTuneAndTheNamesCommandsCarry() async throws {
        let rig = try await keptRig(["Old Lamp", "Blue Avenue", "Smoky Window"])
        let q0 = rig.snap.queue[0]
        #expect(q0.name == "Blue Avenue")
        #expect(await rig.engine.renameTune(TuneTarget(name: "Blue Avenue", index: 0), to: "Avenue at Night") == .success("Avenue at Night"))
        await rig.settle()
        #expect(rig.snap.queue[0].name == "Avenue at Night")
        let n = rig.snapshots.count
        await rig.send(.playQueued(index: 0, name: "Blue Avenue"))
        #expect(rig.snapshots.count == n && rig.snap.tune?.name == "Old Lamp")
        await rig.send(.playQueued(index: 0, name: q0.file))
        #expect(rig.snap.tune?.name == "Avenue at Night")
        await rig.close()
    }

    @Test func refusals() async throws {
        let rig = try await keptRig(["Old Lamp", "Blue Avenue"])
        let gone = Refusal(field: nil, text: "That tune is no longer there.")
        #expect(await rig.engine.renameTune(TuneTarget(name: "Something Else", index: nil), to: "X") == .failure(gone))
        #expect(await rig.engine.renameTune(TuneTarget(name: "Old Lamp", index: 0), to: "X") == .failure(gone))
        #expect(await rig.engine.renameTune(TuneTarget(name: "Old Lamp", index: nil), to: " ") == .failure(Refusal(field: nil, text: "A tune needs a name.")))
        #expect(await rig.engine.renameTune(TuneTarget(name: "Old Lamp", index: nil), to: "a\nb") == .failure(Refusal(field: nil, text: "A name cannot hold control characters or line breaks.")))
        #expect(await rig.engine.renameTune(TuneTarget(name: "Old Lamp", index: nil), to: String(repeating: "x", count: 61))
            == .failure(Refusal(field: nil, text: "A name is at most 60 characters; this one has 61.")))
        #expect(rig.snap.tune?.name == "Old Lamp")
        await rig.close()
    }

    @Test func theSameNameWritesNothing() async throws {
        let rig = try await keptRig(["Old Lamp"])
        let url = rig.genreDir("Jazz").appending(path: rig.tunes("Jazz")[0])
        let sig = Files.signature(url)
        let n = rig.snapshots.count
        #expect(await rig.engine.renameTune(TuneTarget(name: "Old Lamp", index: nil), to: " Old Lamp ") == .success("Old Lamp"))
        await rig.settle()
        #expect(Files.signature(url) == sig && rig.snapshots.count == n)
        await rig.close()
    }

    @Test func aFailedWriteLeavesTheFileAsItWas() async throws {
        let rig = try await keptRig(["Old Lamp"])
        let dir = rig.genreDir("Jazz")
        let url = dir.appending(path: rig.tunes("Jazz")[0])
        let data = FileManager.default.contents(atPath: url.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        let r = await rig.engine.renameTune(TuneTarget(name: "Old Lamp", index: nil), to: "Lamp at Dawn")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        guard case .failure(let refusal) = r else {
            Issue.record("renamed in a folder that cannot be written")
            await rig.close()
            return
        }
        #expect(refusal.field == nil && refusal.text.hasPrefix("could not rename Old Lamp: "))
        #expect(FileManager.default.contents(atPath: url.path) == data)
        #expect(Files.list(dir).filter { $0.hasPrefix(".") }.isEmpty)
        #expect(rig.snap.tune?.name == "Old Lamp")
        await rig.close()
    }

    @Test func onlyTheAppsOwnFiles() async throws {
        let rig = try await keptRig(["Old Lamp"])
        // A tune of the genre found by stem must still be a tune file in a genre folder.
        let r = await rig.engine.renameTune(TuneTarget(name: "../../etc", index: nil), to: "X")
        #expect(r == .failure(Refusal(field: nil, text: "That tune is no longer there.")))
        await rig.close()
    }
}
