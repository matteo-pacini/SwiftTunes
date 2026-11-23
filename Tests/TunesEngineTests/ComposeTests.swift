import AVFoundation
import Foundation
import Testing
import TunesContract
@testable import TunesEngine
import TunesFakes
import TunesRules

@Suite(.serialized) struct ComposeTests {
    @Test func theTwoRequestJobAndTheQueue() async throws {
        let rig = try await Rig()
        await rig.send(.selectGenre(id: "jazz"))
        #expect(rig.snap.genre == "jazz" && rig.snap.player == .none && !rig.snap.stopped)
        await rig.send(.setComposer(on: true))
        #expect(rig.snap.composing)
        #expect(rig.launcher.launches.count == 1)
        #expect(rig.launcher.launches[0] == ["--models", rig.paths.models.path, "--device", "MTL0", "--host", "127.0.0.1", "--port", String(rig.aceHTTP.port)])

        // The first tune is written, rendered, placed, and starts by itself.
        #expect(await rig.run { rig.snap.tune != nil })
        let first = try #require(rig.snap.tune)
        #expect(!first.kept && first.new && first.length != nil && first.wave.count == 78)
        #expect(["C# minor", "F major"].contains(first.key ?? ""))
        #expect(rig.snap.model.device == "Fake M0")
        let lm = await rig.ace.lmCaptions
        #expect(lm.first?.hasPrefix("a late-night jazz trio, brushed drums, upright bass, ") == true)
        #expect(lm.first?.hasSuffix(", instrumental") == true)
        #expect(await rig.ace.lmBPMs.allSatisfy { (90...140).contains($0) })
        #expect(await rig.ace.synthFormats == ["wav16"])
        let files = rig.tunes("Jazz")
        #expect(files.count == 1)
        #expect(rig.player.calls.first == "play \(files[0])")

        // The file is AAC with the tags.
        let url = rig.genreDir("Jazz").appending(path: files[0])
        let audio = try AVAudioFile(forReading: url)
        #expect(audio.fileFormat.settings[AVFormatIDKey] as? UInt32 == kAudioFormatMPEG4AAC)
        let meta = try await AVURLAsset(url: url).load(.metadata)
        let title = try await AVMetadataItem.metadataItems(from: meta, filteredByIdentifier: .iTunesMetadataSongName).first?.load(.stringValue)
        #expect(title == first.name)
        let genre = try await AVMetadataItem.metadataItems(from: meta, filteredByIdentifier: .iTunesMetadataUserGenre).first?.load(.stringValue)
        #expect(genre == "Jazz")
        let comment = try await AVMetadataItem.metadataItems(from: meta, filteredByIdentifier: .iTunesMetadataUserComment).first?.load(.stringValue)
        #expect(comment == "key: \(first.key ?? "")")
        // 12 s of plan, the last 2 s silent and cut.
        #expect(abs((first.length ?? 0) - 10) < 0.2)

        // It keeps composing until two new tunes wait, then rests with no server.
        #expect(await rig.run { rig.snap.ready == 2 && rig.snap.model.state == .idle })
        #expect(rig.launcher.running == 0)
        #expect(rig.snap.model.ramUsedBytes == nil)
        #expect(rig.snap.queue.count >= 2 && rig.snap.queue.prefix(2).allSatisfy(\.new))
        #expect(rig.snap.expect != nil)
        #expect(rig.snap.canNext)
        #expect(rig.tunes("Jazz").count == 3)
        let state = SavedState.parse(Files.read(rig.paths.support.appending(path: "state.json")))
        #expect(state.writing.count == 3 && state.rendering.count == 3)

        // Playing the next one frees a place: the composer starts again.
        rig.player.finish()
        await rig.settle()
        #expect(rig.snap.ready == 1)
        #expect(rig.snap.model.state == .starting || rig.snap.model.state == .writing)
        #expect(rig.launcher.running == 1)
        await rig.send(.setComposer(on: false))
        #expect(rig.snap.model.state == .unloaded && rig.launcher.running == 0)
        await rig.close()
    }

    @Test func jobViewWhileWritingAndRendering() async throws {
        let rig = try await Rig()
        await rig.ace.set(runningPolls: 3)
        await rig.send(.selectGenre(id: "jazz"))
        await rig.send(.setComposer(on: true))
        #expect(await rig.run { rig.snap.job?.stage == .writing })
        #expect(rig.snap.model.state == .writing && rig.snap.job?.started == Rig.start)
        #expect(rig.snap.model.ramUsedBytes == 7_000_000_000)
        #expect(await rig.run { rig.snap.job?.stage == .rendering })
        let job = try #require(rig.snap.job)
        #expect(job.writtenS != nil && job.writtenS! > 0)
        #expect(job.expectS == nil)
        await rig.close()
    }
}
