import AVFoundation
import Foundation
import Testing
import TunesContract
@testable import TunesEngine
import TunesFakes
import TunesRules

private let GiB: Int64 = 1 << 30

/// Two music models, Small and Large: chosen, fetched and removed apart.
@Suite(.serialized, .timeLimit(.minutes(1))) struct ModelChoiceTests {
    static let sungGenres = Rig.genresText.replacingOccurrences(of: "\"bpm\": [90, 140],", with: "\"bpm\": [90, 140],\n      \"sung\": true,")

    func onDisk(_ rig: Rig) -> [String] { Files.list(rig.paths.models).sorted() }
    var shared: [String] { ["fake-dit.gguf", "fake-text.gguf", "fake-vae.gguf"] }
    var large: String { "fake-lm.gguf" }
    var small: String { "fake-lm-small.gguf" }
    func state(_ rig: Rig) -> SavedState { SavedState.parse(Files.read(rig.paths.support.appending(path: "state.json"))) }
    func choice(_ rig: Rig, _ id: String) throws -> ModelChoice { try #require(rig.snap.models.first { $0.id == id }) }

    /// Both models on disk.
    func bothRig(genres: String = Rig.genresText, ahead: Int = 2) async throws -> Rig {
        let rig = try await Rig(ahead: ahead, genres: genres)
        try rig.placeSmall()
        rig.make()
        return rig
    }

    static func modelTag(_ url: URL) async throws -> String? {
        let items = try await AVURLAsset(url: url).load(.metadata)
        return try await AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .iTunesMetadataEncodedBy).first?.load(.stringValue)
    }

    // MARK: - The snapshot

    @Test func theModelsAsTheSnapshotShowsThem() async throws {
        let rig = try await Rig(ready: false, memory: 16 * GiB)
        let s = rig.snap
        #expect(s.memoryBytes == 16 * GiB)
        let sharedBytes = Int64(shared.reduce(0) { $0 + rig.modelFiles[$1]!.count })
        let smallBytes = Int64(rig.smallFile.data.count)
        let largeBytes = Int64(rig.modelFiles[large]!.count)
        #expect(s.models == [
            ModelChoice(id: "small", name: "Small", variant: "0.6B Q8", fileBytes: smallBytes, downloadBytes: smallBytes + sharedBytes,
                        onDisk: false, ramBytes: 4 * GiB, suggested: true, chosen: true, downloading: false),
            ModelChoice(id: "large", name: "Large", variant: "4B Q8", fileBytes: largeBytes, downloadBytes: largeBytes + sharedBytes,
                        onDisk: false, ramBytes: 8 * GiB, suggested: false, chosen: false, downloading: false),
        ])
        // Need and the model line follow the chosen model.
        #expect(s.need.downloadBytes == smallBytes + sharedBytes && s.need.ramBytes == 4 * GiB)
        #expect(s.model.variant == "0.6B Q8")
        #expect(s.setup == .missing)
        await rig.close()
    }

    @Test(arguments: [(8, "small"), (16, "small"), (24, "large"), (32, "large"), (64, "large")] as [(Int64, String)])
    func theSuggestionFollowsTheMemory(memoryGiB: Int64, want: String) async throws {
        let rig = try await Rig(ready: false, memory: memoryGiB * GiB)
        #expect(rig.snap.models.filter(\.suggested).map(\.id) == [want])
        #expect(rig.snap.models.filter(\.chosen).map(\.id) == [want])
        await rig.close()
    }

    @Test func choosingBeforeAnyIsOnDisk() async throws {
        let rig = try await Rig(ready: false, memory: 16 * GiB)
        await rig.send(.chooseModel(id: "large"))
        #expect(try choice(rig, "large").chosen && !choice(rig, "small").chosen)
        #expect(try choice(rig, "small").suggested)
        #expect(rig.snap.need.ramBytes == 8 * GiB && rig.snap.model.variant == "4B Q8")
        // An id the pins do not list is ignored.
        let n = rig.snapshots.count
        await rig.send(.chooseModel(id: "medium"))
        #expect(try rig.snapshots.count == n && choice(rig, "large").chosen)
        await rig.close()
    }

    @Test func onceOneIsOnDiskOnlyAModelOnDiskCanBeChosen() async throws {
        let rig = try await Rig()
        #expect(try choice(rig, "large").chosen && choice(rig, "large").onDisk && !choice(rig, "small").onDisk)
        await rig.send(.chooseModel(id: "small"))
        #expect(try choice(rig, "large").chosen)
        #expect(state(rig).model == nil)
        await rig.close()
    }

    // MARK: - The chosen model, kept

    @Test func theChoiceSurvivesARestart() async throws {
        let rig = try await bothRig()
        #expect(try choice(rig, "large").chosen)
        await rig.send(.chooseModel(id: "small"))
        #expect(try choice(rig, "small").chosen && rig.snap.setup == .ready)
        #expect(state(rig).model == "small")
        await rig.shutdown()
        rig.make()
        #expect(try choice(rig, "small").chosen && rig.snap.model.variant == "0.6B Q8")
        await rig.close()
    }

    @Test(arguments: [(true, true, "large"), (true, false, "small"), (false, true, "large")])
    func anOldStateFileMeansTheModelOnDisk(smallOnDisk: Bool, largeOnDisk: Bool, want: String) async throws {
        let rig = try await Rig(ready: false, memory: 8 * GiB)
        if smallOnDisk { try rig.placeSmall() }
        if largeOnDisk { try rig.placeModels() }
        try Files.makeDirectory(rig.paths.support)
        let old = #"{"writing": [60.0, 62.0], "rendering": [40.0], "shuffle": true, "repeat": "all", "volume": 1.0}"#
        try Data(old.utf8).write(to: rig.paths.support.appending(path: "state.json"))
        rig.make()
        #expect(rig.snap.models.filter(\.chosen).map(\.id) == [want])
        #expect(rig.snap.setup == .ready)
        // The timings already saved are Large's.
        #expect(rig.snap.expect == (want == "large" ? Expect(writingS: 61, renderingS: 40) : nil))
        await rig.close()
    }

    // MARK: - The server

    @Test func everyLMRequestNamesItsModel() async throws {
        let rig = try await Rig()
        // A silent plan is written again: that request names the model too.
        await rig.ace.set(kinds: [.silent, .normal, .normal])
        await rig.send(.selectGenre(id: "jazz"))
        await rig.send(.setComposer(on: true))
        #expect(await rig.run { rig.snap.ready == 2 })
        let models = await rig.ace.lmModels
        #expect(models.count >= 3 && models.allSatisfy { $0 == large })
        await rig.close()
    }

    @Test func aChangeAppliesFromTheNextTune() async throws {
        let rig = try await bothRig()
        await rig.ace.set(runningPolls: 20)
        await rig.send(.selectGenre(id: "jazz"))
        await rig.send(.setComposer(on: true))
        #expect(await rig.run { rig.snap.model.state == .writing })
        await rig.send(.chooseModel(id: "small"))
        #expect(rig.snap.job?.stage == .writing && rig.snap.model.variant == "0.6B Q8")
        #expect(rig.engine.job?.model?.id == "large")
        #expect(await rig.run { rig.snap.ready == 2 })
        // The first tune plays; the two after it wait, both made with Small.
        #expect(await rig.ace.lmModels == [large, small, small])
        await rig.close()
    }

    @Test func aTuneWithWordsUsesItsOwnModel() async throws {
        let rig = try await bothRig(genres: Self.sungGenres, ahead: 1)
        await rig.send(.selectGenre(id: "jazz"))
        await rig.send(.stop)
        #expect(refusal(await rig.engine.composeWithWords("hold on to me", name: "Mine", model: "small")) == nil)
        #expect(await rig.run { rig.snap.ready == 1 && rig.snap.job == nil })
        // That tune alone: the chosen model stays and makes the next.
        #expect(try choice(rig, "large").chosen)
        await rig.send(.setComposer(on: true))
        #expect(await rig.run { rig.snap.ready == 1 && rig.snap.model.state == .idle })
        #expect(await rig.ace.lmModels == [small])
        await rig.close()
    }

    @Test(arguments: [nil, "small", "medium"] as [String?])
    func wordsForNoModelOrOneNotOnDiskUseTheChosenOne(model: String?) async throws {
        let rig = try await Rig(genres: Self.sungGenres)
        await rig.send(.selectGenre(id: "jazz"))
        await rig.send(.stop)
        #expect(refusal(await rig.engine.composeWithWords("hold on to me", name: "Mine", model: model)) == nil)
        #expect(await rig.run { rig.snap.ready == 1 && rig.snap.job == nil })
        #expect(await rig.ace.lmModels == [large])
        await rig.close()
    }

    @Test func aLanguageModelThePinsDoNotNameIsNeitherUsedNorDeleted() async throws {
        let rig = try await Rig()
        // First by name: the server would take it if no model were named.
        let stray = rig.paths.models.appending(path: "aaa-lm.gguf")
        try Data("not ours".utf8).write(to: stray)
        await rig.send(.selectGenre(id: "jazz"))
        await rig.send(.setComposer(on: true))
        #expect(await rig.run { rig.snap.ready == 2 })
        #expect(await rig.ace.lmModels.allSatisfy { $0 == large })
        await rig.send(.removeModel)
        #expect(onDisk(rig) == ["aaa-lm.gguf"])
        await rig.close()
    }

    // MARK: - What is kept per model

    @Test func timingsArePerModel() async throws {
        let rig = try await bothRig(ahead: 1)
        await rig.send(.selectGenre(id: "jazz"))
        await rig.send(.setComposer(on: true))
        #expect(await rig.run { rig.snap.ready == 1 && rig.snap.model.state == .idle })
        let largeExpect = try #require(rig.snap.expect)
        // Small has no timings yet: no estimate while it is chosen.
        await rig.send(.chooseModel(id: "small"))
        #expect(rig.snap.expect == nil)
        rig.player.finish()
        #expect(await rig.run { rig.snap.ready == 1 && rig.snap.model.state == .idle })
        #expect(rig.snap.expect != nil)
        let saved = state(rig)
        #expect(saved.timings["large"]?.writing.isEmpty == false && saved.timings["small"]?.writing.count == 1)
        #expect(await rig.ace.lmModels.last == small)
        await rig.send(.chooseModel(id: "large"))
        #expect(rig.snap.expect == largeExpect)
        await rig.close()
    }

    @Test func aTunesFileRecordsItsModel() async throws {
        let rig = try await bothRig(ahead: 1)
        await rig.send(.chooseModel(id: "small"))
        await rig.send(.selectGenre(id: "jazz"))
        await rig.send(.setComposer(on: true))
        #expect(await rig.run { rig.snap.ready == 1 })
        let file = try #require(rig.tunes("Jazz").first)
        #expect(try await Self.modelTag(rig.genreDir("Jazz").appending(path: file)) == "small")
        await rig.close()
    }

    // MARK: - Downloads

    @Test(arguments: ["small", "large"])
    func theFirstDownloadOfEachChoice(id: String) async throws {
        let rig = try await Rig(ready: false, memory: 8 * GiB)
        await rig.send(.chooseModel(id: id))
        rig.engine.send(.download)
        #expect(rig.engine.dl?.model == id && rig.engine.dl?.files == 4)
        #expect(await rig.run { rig.snap.setup == .ready })
        let own = id == "small" ? small : large
        #expect(onDisk(rig) == ([own] + shared).sorted())
        #expect(try choice(rig, id).onDisk && choice(rig, id).chosen && choice(rig, id).downloadBytes == 0)
        let requests = await rig.host.requests
        #expect(!requests.contains { $0.hasSuffix("/" + (id == "small" ? large : small)) })
        await rig.close()
    }

    @Test func aSecondModelFetchesOneFileWhileComposing() async throws {
        let rig = try await Rig(ahead: 1)
        await rig.ace.set(runningPolls: 20)
        await rig.send(.selectGenre(id: "jazz"))
        await rig.send(.setComposer(on: true))
        #expect(await rig.run { rig.snap.model.state == .writing })
        rig.engine.send(.downloadModel(id: "small"))
        let d = try #require(rig.engine.dl)
        #expect(d.model == "small" && d.files == 1 && d.file == 1 && d.name == "language model")
        #expect(d.total == Int64(rig.smallFile.data.count))
        let during = rig.engine.buildSnapshot()
        #expect(during.models.map(\.downloading) == [true, false])
        // The chosen model stays ready and composes meanwhile.
        #expect(during.setup == .ready && during.composing)
        #expect(await rig.run { rig.snap.download == nil && rig.snap.ready == 1 })
        #expect(try choice(rig, "small").onDisk)
        #expect(await rig.host.requests == ["/resolve/rev/" + small])
        #expect(await rig.ace.cancelled.isEmpty)
        #expect(await rig.ace.lmModels.allSatisfy { $0 == large })
        #expect(try choice(rig, "large").chosen && rig.snap.setup == .ready && rig.snap.composing)
        await rig.close()
    }

    @Test func oneDownloadAtATime() async throws {
        let rig = try await Rig(ready: false, memory: 8 * GiB)
        await rig.host.set(holdAfter: 500)
        rig.engine.send(.download)
        await rig.host.untilHeld()
        #expect(rig.engine.dl?.model == "small")
        let task = rig.engine.dlTask
        rig.engine.send(.downloadModel(id: "large"))
        #expect(rig.engine.dlTask == task && rig.engine.dl?.model == "small")
        #expect(rig.engine.buildSnapshot().models.map(\.downloading) == [true, false])
        await rig.host.release()
        #expect(await rig.run { rig.snap.setup == .ready })
        // Its own file on disk: asking again does nothing.
        await rig.send(.downloadModel(id: "small"))
        #expect(rig.snap.download == nil)
        await rig.close()
    }

    @Test func aFailedDownloadOfAnotherModelResumesThroughDownloadModel() async throws {
        let rig = try await Rig()
        await rig.host.set(corrupt: [small])
        await rig.send(.downloadModel(id: "small"))
        #expect(await rig.run { rig.snap.download?.error != nil })
        #expect(rig.snap.download?.error == "\(small): checksum mismatch" && rig.snap.download?.model == "small")
        // The chosen model is still ready.
        #expect(rig.snap.setup == .ready)
        await rig.host.set(corrupt: [])
        await rig.send(.downloadModel(id: "small"))
        #expect(rig.snap.download?.error == nil)
        #expect(await rig.run { rig.snap.download == nil })
        #expect(try choice(rig, "small").onDisk)
        await rig.close()
    }

    @Test func aCancelledDownloadOfAnotherModelResumesFromItsPart() async throws {
        let rig = try await Rig()
        await rig.host.set(holdAfter: 1000)
        rig.engine.send(.downloadModel(id: "small"))
        await rig.host.untilHeld()
        await rig.send(.cancelDownload)
        await rig.host.release()
        await rig.settle()
        #expect(rig.snap.download == nil)
        // How much reached the part before the cancel depends on timing:
        // the first 1000 bytes stand for it.
        try rig.smallFile.data.prefix(1000).write(to: rig.paths.models.appending(path: small + ".part"))
        await rig.send(.downloadModel(id: "small"))
        #expect(await rig.run { rig.snap.download == nil })
        #expect(await rig.host.ranges.last == "bytes=1000-")
        #expect(FileManager.default.contents(atPath: rig.paths.models.appending(path: small).path) == rig.smallFile.data)
        await rig.close()
    }

    // MARK: - Removing

    @Test func removingOneLeavesTheOthersFiles() async throws {
        let rig = try await bothRig()
        try Data("part".utf8).write(to: rig.paths.models.appending(path: small + ".part"))
        await rig.send(.removeOneModel(id: "small"))
        #expect(onDisk(rig) == ([large] + shared).sorted())
        #expect(try !choice(rig, "small").onDisk && choice(rig, "large").onDisk && choice(rig, "large").chosen)
        #expect(rig.snap.setup == .ready && rig.snap.error == nil)
        await rig.close()
    }

    @Test func theChosenOneIsRefusedWhileAnotherIsOnDisk() async throws {
        let rig = try await bothRig()
        let n = rig.snapshots.count
        await rig.send(.removeOneModel(id: "large"))
        #expect(rig.snapshots.count == n)
        #expect(onDisk(rig) == ([small, large] + shared).sorted())
        await rig.close()
    }

    @Test func removingTheLastIsRemovingTheModel() async throws {
        let rig = try await Rig()
        await rig.send(.selectGenre(id: "jazz"))
        await rig.send(.setComposer(on: true))
        #expect(rig.snap.composing)
        await rig.send(.removeOneModel(id: "large"))
        #expect(await rig.run { rig.launcher.running == 0 })
        #expect(onDisk(rig).isEmpty && !rig.snap.composing && rig.snap.setup == .missing)
        #expect(rig.snap.need.onDiskBytes == 0)
        await rig.close()
    }

    @Test func removingTheModelTakesEveryListedFile() async throws {
        let rig = try await bothRig()
        await rig.send(.removeModel)
        #expect(onDisk(rig).isEmpty && rig.snap.need.onDiskBytes == 0)
        await rig.close()
    }
}

/// The pins file as the engine reads it.
@Suite struct PinsTests {
    static let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test func theRepositorysPinsListTwoModels() throws {
        let pins = try Pins.parse(try #require(Files.read(Self.repo.appending(path: "Config/pins.json"))))
        #expect(pins.choices.map(\.id) == ["small", "large"])
        #expect(pins.choices.map(\.variant) == ["0.6B Q8", "4B Q8"])
        #expect(pins.choices.map(\.file.name) == ["acestep-5Hz-lm-0.6B-Q8_0.gguf", "acestep-5Hz-lm-4B-Q8_0.gguf"])
        #expect(pins.choices.map(\.ramBytes) == [4 * GiB, 8 * GiB])
        #expect(pins.shared.map(\.role) == ["dit", "text", "vae"])
        #expect(pins.shared.reduce(0) { $0 + $1.bytes } == 3_671_093_888)
        // What each would download into an empty folder.
        let none: [String: Int64] = [:]
        let need = pins.choices.map { c in TuneFiles.needBytes(([c.file] + pins.shared).map { ($0.name, $0.bytes) }, present: none) }
        #expect(need == [4_380_940_544, 8_128_417_536])
        let suggested = [8, 16, 24, 32, 64].map { pins.choices[ModelRules.suggested(from: pins.choices.map(\.suggestedFrom), memory: $0 * GiB)].id }
        #expect(suggested == ["small", "small", "large", "large", "large"])
    }

    nonisolated static let file = #"{"role": "lm", "name": "a.gguf", "sha256": "AB", "bytes": 1}"#
    nonisolated static let dit = #"{"role": "dit", "name": "d.gguf", "sha256": "cd", "bytes": 2}"#
    nonisolated static func pins(shared: String = "[\(dit)]", choices: String) -> String {
        #"{"model": {"name": "M", "base_url": "u", "revision": "r", "silence_code": 1, "shared": \#(shared), "choices": \#(choices)}, "keep": 1, "ahead": 1, "duration": 1}"#
    }
    nonisolated static func choice(id: String = "a", file: String = file, from: String = "0") -> String {
        #"{"id": "\#(id)", "name": "A", "variant": "V", "file": \#(file), "ram_bytes": 4, "suggested_from_bytes": \#(from)}"#
    }

    @Test func aGoodOne() throws {
        let p = try Pins.parse(Self.pins(choices: "[\(Self.choice())]"))
        #expect(p.choices.first?.file == ModelFile(role: "lm", name: "a.gguf", sha256: "ab", bytes: 1))
        #expect(p.choices.first?.suggestedFrom == 0 && p.files.map(\.name) == ["a.gguf", "d.gguf"])
    }

    @Test(arguments: [
        (pins(choices: "[]"), "model.choices"),
        (pins(shared: "[]", choices: "[\(choice())]"), "model.shared"),
        (pins(choices: "[\(choice()), \(choice())]"), "model.choices[1].id"),
        (pins(choices: "[\(choice(id: ""))]"), "model.choices[0].id"),
        (pins(choices: "[\(choice(file: dit))]"), "model.choices[0].file.role"),
        (pins(choices: "[\(choice(from: "-1"))]"), "model.choices[0].suggested_from_bytes"),
        (pins(shared: #"[{"role": "x", "name": "d", "sha256": "c", "bytes": 2}]"#, choices: "[\(choice())]"), "model.shared[0].role"),
    ])
    func aWrongOne(text: String, key: String) {
        #expect(throws: Pins.Mistake.self) { try Pins.parse(text) }
        do {
            _ = try Pins.parse(text)
        } catch {
            #expect(error.description == key)
        }
    }
}
