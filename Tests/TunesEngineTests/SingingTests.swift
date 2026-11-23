import AVFoundation
import Foundation
import Testing
import TunesContract
@testable import TunesEngine
import TunesFakes
import TunesRules

/// Sung genres, the words in the file, thin words, and the user's own words.
@Suite(.serialized, .timeLimit(.minutes(1))) struct SingingTests {
    /// The rig's genres with Jazz sung.
    static let sungGenres = Rig.genresText.replacingOccurrences(of: "\"bpm\": [90, 140],", with: "\"bpm\": [90, 140],\n      \"sung\": true,")

    func sungRig(ahead: Int = 2) async throws -> Rig {
        let rig = try await Rig(ahead: ahead, genres: Self.sungGenres)
        await rig.send(.selectGenre(id: "jazz"))
        return rig
    }

    static func lyricsTag(_ url: URL) async throws -> String? {
        let items = try await AVURLAsset(url: url).load(.metadata)
        return try await AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .iTunesMetadataLyrics).first?.load(.stringValue)
    }

    @Test func theGenresFileSaysWhichGenresAreSung() async throws {
        let rig = try await sungRig()
        #expect(rig.snap.genres.map(\.sung) == [true, false])
        let jazz = try await rig.engine.genre(id: "jazz").get()
        #expect(jazz.sung)
        var lofi = try await rig.engine.genre(id: "lofi").get()
        lofi.sung = true
        #expect(await rig.engine.saveGenre(id: "lofi", fields: lofi, base: try await rig.engine.genre(id: "lofi").get()) == .success(GenreSaved(id: "lofi", renamed: nil)))
        await rig.settle()
        #expect(rig.snap.genres.map(\.sung) == [true, true])
        let text = try #require(Files.read(rig.paths.support.appending(path: "genres.json")))
        #expect(text.contains("\"bpm\": [70, 92],\n      \"sung\": true"))
        await rig.close()
    }

    @Test func theRequestShapes() async throws {
        let rig = try await sungRig()
        await rig.send(.stop)
        await rig.send(.setComposer(on: true))
        #expect(await rig.run { rig.snap.ready == 1 })
        await rig.send(.selectGenre(id: "lofi"))
        await rig.send(.setComposer(on: true))
        #expect(await rig.run { rig.snap.ready == 1 })
        let captions = await rig.ace.lmCaptions
        let lyrics = await rig.ace.lmLyrics
        let languages = await rig.ace.lmLanguages
        #expect(lyrics.first == "" && languages.first == "en")
        #expect(captions.first?.hasPrefix("a late-night jazz trio, brushed drums, upright bass") == true)
        #expect(captions.first?.contains("instrumental") == false)
        #expect(lyrics.last == "[Instrumental]" && languages.last == .some(nil))
        #expect(captions.last?.hasSuffix(", instrumental") == true)
        await rig.close()
    }

    @Test func theWordsAreKeptInTheFileAndReadBack() async throws {
        let rig = try await sungRig()
        await rig.send(.setComposer(on: true))
        #expect(await rig.run { rig.snap.tune != nil && rig.snap.ready >= 1 })
        let tune = try #require(rig.snap.tune)
        #expect(tune.sung && tune.lyrics == FakeAceServer.words)
        #expect(rig.snap.queue.first?.sung == true)
        let url = rig.genreDir("Jazz").appending(path: tune.file + ".m4a")
        #expect(try await Self.lyricsTag(url) == FakeAceServer.words)
        // A rename rewrites the title and keeps the words.
        #expect(await rig.engine.renameTune(TuneTarget(name: tune.name, index: nil), to: "Amber Lights") == .success("Amber Lights"))
        #expect(try await Self.lyricsTag(url) == FakeAceServer.words)
        await rig.send(.setComposer(on: false))
        // After a restart, from the wave cache, and from the file itself.
        rig.make()
        await rig.send(.setShuffle(on: false))
        await rig.send(.selectGenre(id: "jazz"))
        let all = [rig.snap.tune] .compactMap { $0 }
        #expect(all.allSatisfy { $0.sung && $0.lyrics == FakeAceServer.words })
        Files.removeTree(rig.paths.caches.appending(path: "wave"))
        let kept = try #require(rig.engine.keptNames().first)
        let meta = try await AudioWork.meta(of: rig.genreDir("Jazz").appending(path: kept))
        #expect(meta.lyrics == FakeAceServer.words)
        await rig.close()
    }

    @Test func thinWordsAreWrittenAgainWithTheirOwnCount() async throws {
        let rig = try await sungRig()
        await rig.ace.set(kinds: [.thin, .declines, .normal])
        await rig.send(.setComposer(on: true))
        #expect(await rig.run { rig.snap.tune != nil })
        #expect(rig.snapshots.contains { $0.model.thinWords && $0.model.state == .writing && $0.model.silenceS == nil })
        #expect(!rig.snap.model.thinWords && rig.snap.model.failures == 0)
        await rig.close()
    }

    @Test func theThirdThinPlanIsAFailure() async throws {
        let rig = try await sungRig()
        await rig.ace.set(kinds: [.declines, .thin, .declines])
        await rig.send(.setComposer(on: true))
        #expect(await rig.run { rig.snap.model.state == .failed })
        #expect(rig.snap.model.detail == "3 plans in a row had too few sung lines")
        #expect(!rig.snap.model.thinWords)
        await rig.close()
    }

    @Test func silenceAndThinWordsCountApart() async throws {
        let rig = try await sungRig()
        await rig.ace.set(kinds: [.silent, .thin, .silent, .thin, .normal])
        await rig.send(.setComposer(on: true))
        #expect(await rig.run { rig.snap.tune != nil })
        let count = await rig.ace.lmCount
        #expect(rig.snap.model.failures == 0 && count >= 5)
        await rig.close()
    }

    @Test func ownWordsWithTheSwitchOff() async throws {
        let rig = try await sungRig()
        await rig.send(.stop)
        let words = "[Verse]\nonly one line of mine"
        #expect(refusal(await rig.engine.composeWithWords(words, name: "  Blue Walk ")) == nil)
        await rig.settle()
        #expect(!rig.snap.composing && rig.launcher.launches.count == 1)
        #expect(await rig.run { rig.snap.job?.ownWords == true })
        let job = try #require(rig.snap.job)
        #expect(job.sung && job.name == "Blue Walk" && job.stage == .writing && rig.snap.model.state == .writing)
        #expect(await rig.run { rig.snap.ready == 1 && rig.snap.job == nil })
        // Sent as given, with no thin check, the language asked for.
        let sent = await rig.ace.lmLyrics
        let languages = await rig.ace.lmLanguages
        #expect(sent == [words] && languages == ["en"])
        let made = try #require(rig.snap.queue.first)
        #expect(made.name == "Blue Walk" && made.sung && made.new)
        // Made once: the server stops and the composer stays off.
        #expect(rig.launcher.running == 0 && rig.snap.model.state == .unloaded && !rig.snap.composing)
        await rig.close()
    }

    @Test func ownWordsComeFirstEvenWithTheQueueFull() async throws {
        let rig = try await sungRig(ahead: 1)
        await rig.send(.stop)
        await rig.send(.setComposer(on: true))
        #expect(await rig.run { rig.snap.ready == 1 && rig.snap.model.state == .idle })
        #expect(refusal(await rig.engine.composeWithWords("hold on to me", name: "Mine")) == nil)
        #expect(await rig.run { rig.snap.ready == 2 })
        #expect(rig.snap.queue.first?.name == "Mine")
        #expect(await rig.run { rig.snap.model.state == .idle && rig.launcher.running == 0 })
        await rig.close()
    }

    @Test func refusals() async throws {
        let rig = try await sungRig()
        #expect(refusal(await rig.engine.composeWithWords("[Verse]", name: "X")) == Refusal(field: nil, text: "A tune needs at least one sung line."))
        #expect(refusal(await rig.engine.composeWithWords("la", name: " ")) == Refusal(field: nil, text: "A tune needs a name."))
        await rig.ace.set(holdLM: true)
        #expect(refusal(await rig.engine.composeWithWords("la", name: "One")) == nil)
        #expect(refusal(await rig.engine.composeWithWords("la", name: "Two")) == Refusal(field: nil, text: "A tune with your words is already being made."))
        await rig.ace.releaseLM()
        await rig.send(.selectGenre(id: "lofi"))
        #expect(refusal(await rig.engine.composeWithWords("la", name: "Three")) == Refusal(field: nil, text: "That genre is not sung."))
        await rig.close()
    }

    @Test func scrappingTheJobCancelsTheWords() async throws {
        let rig = try await sungRig()
        await rig.ace.set(runningPolls: 100)
        #expect(refusal(await rig.engine.composeWithWords("la", name: "Mine")) == nil)
        #expect(await rig.run { rig.snap.job?.ownWords == true && rig.snap.model.state == .writing })
        await rig.send(.scrapJob)
        #expect(rig.snap.job == nil && rig.engine.ownWordsPending == nil)
        #expect(await rig.ace.cancelled.count == 1)
        #expect(await rig.run { rig.launcher.running == 0 })
        #expect(rig.snap.model.state == .unloaded)
        await rig.close()
    }

    @Test func aFailedOwnWordsTuneIsTriedAgain() async throws {
        let rig = try await sungRig()
        await rig.send(.stop)
        await rig.ace.set(kinds: [.fail])
        #expect(refusal(await rig.engine.composeWithWords("la la", name: "Mine")) == nil)
        #expect(await rig.run { rig.snap.model.state == .failed })
        #expect(await rig.run { rig.snap.ready == 1 })
        let sent = await rig.ace.lmLyrics
        #expect(rig.snap.queue.first?.name == "Mine" && sent == ["la la", "la la"])
        await rig.close()
    }

    @Test func aHoldWaitsForTheWords() async throws {
        let rig = try await sungRig()
        await rig.send(.stop)
        rig.holds.hold = .heat
        #expect(refusal(await rig.engine.composeWithWords("la la", name: "Mine")) == nil)
        await rig.settle()
        #expect(rig.snap.model.state == .heldHeat && rig.launcher.launches.isEmpty)
        rig.holds.hold = nil
        #expect(await rig.run { rig.snap.ready == 1 })
        await rig.close()
    }

    @Test func pickingAnotherGenreDropsTheWords() async throws {
        let rig = try await sungRig()
        await rig.ace.set(runningPolls: 100)
        #expect(refusal(await rig.engine.composeWithWords("la", name: "Mine")) == nil)
        #expect(await rig.run { rig.snap.job?.ownWords == true })
        await rig.send(.selectGenre(id: "lofi"))
        #expect(rig.snap.job == nil && rig.engine.ownWordsPending == nil)
        #expect(await rig.run { rig.launcher.running == 0 })
        await rig.close()
    }
}
