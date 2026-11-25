import Testing
import TunesContract
@testable import TunesPanel

func models(_ s: Snapshot, _ p: Panel = Panel().openingModels()) throws -> ModelsCard {
    guard case .models(let c) = card(s, p) else {
        Issue.record("not the models card: \(card(s, p))")
        throw CancellationError()
    }
    return c
}

/// The capsule at the end of a composer line, with the line's text.
func capsules(_ p: PlayerCard) -> [(String, Control)] {
    p.composer.lines.compactMap { l in l.models.map { (l.text, $0) } }
}

let note = " Large follows the prompt and the words more closely; Small is quicker and lighter. You can add the other later."

@Suite("Music models: the first run")
struct ModelsSetupTests {
    @Test("16 GiB: Small suggested and chosen, a row per model, the memory sentence, no memory row")
    func sixteen() throws {
        let c = try setup(Fixture.load("48-models-first-16gib"))
        #expect(c.kind == .missing && c.title == "SwiftTunes needs a music model")
        #expect(c.detail == "ACE-Step 1.5 Turbo composes on this computer. Nothing is sent anywhere after the download.")
        #expect(c.models == [
            SetupCard.Choice(id: "small", name: "Small", variant: "0.6B Q8", chosen: true, tag: "Suggested",
                             sub: "4.08 GiB download · about 4 GiB of memory",
                             control: Control(lit: true, text: "Small", help: "Small"), command: .chooseModel(id: "small")),
            SetupCard.Choice(id: "large", name: "Large", variant: "4B Q8", chosen: false, tag: "",
                             sub: "7.57 GiB download · about 8 GiB of memory",
                             control: Control(text: "Large", help: "Large"), command: .chooseModel(id: "large")),
        ])
        #expect(c.modelsNote == "This Mac has 16 GiB of memory." + note)
        #expect(c.rows.map { [$0.label, $0.value] } == [["download", "4.08 GiB"], ["free on disk", "226 GiB"]])
        #expect(c.button.text == "Download" && c.command == .download)
    }

    @Test("64 GiB: Large suggested and chosen")
    func sixtyFour() throws {
        let c = try setup(Fixture.load("49-models-first-64gib"))
        #expect(c.models.map { [$0.id, $0.tag, "\($0.chosen)", "\($0.control.lit)"] } == [["small", "", "false", "false"], ["large", "Suggested", "true", "true"]])
        #expect(c.modelsNote == "This Mac has 64 GiB of memory." + note)
        #expect(c.rows.map { [$0.label, $0.value] } == [["download", "7.57 GiB"], ["free on disk", "226 GiB"]])
    }

    @Test("with the memory unknown the sentence leaves it out")
    func noMemory() throws {
        var s = try Fixture.load("48-models-first-16gib")
        s.memoryBytes = 0
        #expect(try setup(s).modelsNote == String(note.dropFirst()))
    }

    @Test("with no models listed: today's card, the memory row, no model rows")
    func noModels() throws {
        let c = try setup(Fixture.load("01-not-set-up"))
        #expect(c.models.isEmpty && c.modelsNote.isEmpty)
        #expect(c.rows.map(\.label) == ["download", "free on disk", "memory while composing"])
    }

    @Test("downloading and failed cards list no models", arguments: ["02-downloading", "03-download-failed"])
    func notWhileFetching(_ name: String) throws {
        var s = try Fixture.load(name)
        s.models = try Fixture.load("49-models-first-64gib").models
        s.memoryBytes = 68_719_476_736
        let c = try setup(s)
        #expect(c.models.isEmpty && c.modelsNote.isEmpty)
    }
}

@Suite("Music models: the composer bar")
struct ModelsComposerTests {
    @Test("the model line without the variant, ending in the capsule")
    func modelLine() throws {
        let p = try player(Fixture.load("50-models-large-only"))
        #expect(lines(p) == ["Makes Jazz, keeps 2 ahead | using 5.8 GiB of memory", "ACE-Step 1.5 Turbo · Apple M4 Pro"])
        let caps = capsules(p)
        #expect(caps.count == 1)
        #expect(caps.first?.0 == "ACE-Step 1.5 Turbo · Apple M4 Pro")
        #expect(caps.first?.1 == Control(text: "Large", help: "Music models"))
    }

    @Test("resting and off: the capsule on a line of its own", arguments: [
        ("51-models-both-large-chosen", ["Makes Jazz, keeps 2 ahead | resting, queue is full", ""]),
        ("53-models-second-failed", ["On, it makes new Jazz and keeps 2 ahead.", ""]),
    ])
    func ownLine(_ name: String, _ expected: [String]) throws {
        let p = try player(Fixture.load(name))
        #expect(lines(p) == expected)
        #expect(capsules(p).map(\.0) == [""])
        #expect(capsules(p).map(\.1) == [Control(text: "Large", help: "Music models")])
    }

    @Test("the capsule names the chosen model")
    func chosenName() throws {
        var s = try Fixture.load("51-models-both-large-chosen")
        s.models[0].chosen = true
        s.models[1].chosen = false
        #expect(capsules(try player(s)).map(\.1.text) == ["Small"])
    }

    @Test("failed: the capsule ends the model line, beside Try now")
    func failed() throws {
        var s = try Fixture.load("15-failed-playing")
        s.models = try Fixture.load("50-models-large-only").models
        let p = try player(s)
        #expect(capsules(p).map(\.0) == ["ACE-Step 1.5 Turbo · Apple M4 Pro"])
        #expect(p.composer.lines.last?.models != nil && p.composer.retry != nil)
    }

    @Test("held, no device and the stand-in: no capsule", arguments: [ModelState.heldPower, .heldHeat, .heldMemory, .noDevice])
    func none(_ state: ModelState) throws {
        var s = try Fixture.load("51-models-both-large-chosen")
        s.model.state = state
        #expect(capsules(try player(s)).isEmpty)
    }

    @Test("the stand-in is unchanged")
    func standIn() throws {
        var s = try Fixture.load("41-no-model-kept")
        s.models = try Fixture.load("48-models-first-16gib").models
        let c = try player(s).composer
        #expect(c.lines.isEmpty && c.standIn?.command == .download)
    }

    static let withModelLine = ["06-first-tune", "10-writing", "11-after-scrap", "15-failed-playing", "19-outside-text", "20-session", "22-writing-again",
                            "25-kept-playing-new-ready", "36-sung-lyrics", "37-thin-rewrite", "38-own-words", "39-twelve-queue",
                            "40-twelve-repeat-off", "45-round-played", "47-round-fifty"]
    static let withoutModelLine = ["05-queue-full", "07-composer-off-kept", "08-nothing-kept", "09-kept-tunes", "12-held-power", "13-held-memory",
                              "14-no-device", "16-genres-error", "17-paused", "21-stopped", "23-pick-after-pause", "24-pick-after-stop",
                              "29-after-save", "30-modes-default", "31-shuffle-off", "32-repeat-one", "33-ended", "34-pinned",
                              "41-no-model-kept", "42-downloading-kept", "43-download-failed-kept", "44-model-on-disk", "46-round-ended"]

    @Test("with no models listed: the variant on the model line and no capsule", arguments: withModelLine)
    func noModels(_ name: String) throws {
        let s = try Fixture.load(name)
        #expect(s.models.isEmpty && !s.model.variant.isEmpty)
        let p = try player(s)
        #expect(lines(p).contains([s.model.name, s.model.variant, s.model.device].joined(separator: " · ")))
        #expect(capsules(p).isEmpty)
    }

    @Test("with no models listed and no model line: no capsule", arguments: withoutModelLine)
    func noModelsNoLine(_ name: String) throws {
        let s = try Fixture.load(name)
        #expect(s.models.isEmpty)
        #expect(capsules(try player(s)).isEmpty)
    }

    @Test("every player fixture without models is in one of the two lists")
    func listsComplete() throws {
        let players = try Fixture.states.filter { !$0.contains("-models-") }.filter { name in
            if case .player = card(try Fixture.load(name)) { return true }
            return false
        }
        #expect(Set(players) == Set(Self.withModelLine + Self.withoutModelLine))
    }
}

@Suite("Music models: the card")
struct ModelsCardTests {
    let header = ("MUSIC MODELS", "Music models", "New tunes are made with the ticked one. A change applies from the next tune.",
                  "The models share 3.42 GiB of other files, kept while a model remains. This card is also under Music Models… in the menu bar icon's menu.")

    func buttons(_ r: ModelsCard.Row) -> [String] { r.buttons.map(\.control.text) }

    @Test("the capsule opens it; Back and Esc return to the player")
    func moving() throws {
        let s = try Fixture.load("50-models-large-only")
        let p = Panel().openingModels()
        #expect(p.mode == .models)
        let c = try models(s, p)
        #expect(c.back == Control(text: "Back", help: "Back"))
        #expect([c.label, c.title, c.detail, c.footnote] == [header.0, header.1, header.2, header.3])
        #expect(p.backToPlayer().mode == .player)
        let (esc, close) = p.escaping(s)
        #expect(esc.mode == .player && !close)
    }

    @Test("it shows over the setup cards, and Esc still returns")
    func overSetup() throws {
        let s = try Fixture.load("48-models-first-16gib")
        let p = Panel().openingModels()
        _ = try models(s, p)
        #expect(p.escaping(s).panel.mode == .player && !p.escaping(s).close)
    }

    @Test("Large on disk and chosen, Small not: Download on Small; Remove on Large, the only one, as removing the music model")
    func largeOnly() throws {
        let s = try Fixture.load("50-models-large-only")
        let c = try models(s)
        let small = c.rows[0], large = c.rows[1]
        #expect([small.id, small.name, small.variant] == ["small", "Small", "0.6B Q8"])
        #expect(!small.ticked && small.sub == "0.66 GiB to download · about 4 GiB of memory" && small.progress == nil && small.error.isEmpty)
        #expect(small.buttons == [ModelsCard.Button(kind: .download, control: Control(text: "Download", help: "Download Small"), command: .downloadModel(id: "small"), ask: nil)])
        #expect(large.ticked && large.sub == "4.15 GiB on this Mac · about 8 GiB of memory")
        var last = Decide.modelRemoval(s)
        last.command = .removeOneModel(id: "large")
        #expect(large.buttons == [ModelsCard.Button(kind: .remove, control: Control(text: "Remove", help: "Remove Large"), command: .removeOneModel(id: "large"), ask: last)])
    }

    @Test("both on disk, Large chosen: Use and Remove on Small, nothing on Large")
    func both() throws {
        let c = try models(Fixture.load("51-models-both-large-chosen"))
        let small = c.rows[0], large = c.rows[1]
        #expect(small.sub == "0.66 GiB on this Mac · about 4 GiB of memory" && !small.ticked)
        #expect(small.buttons == [
            ModelsCard.Button(kind: .use, control: Control(text: "Use", help: "Use Small"), command: .chooseModel(id: "small"), ask: nil),
            ModelsCard.Button(kind: .remove, control: Control(text: "Remove", help: "Remove Small"), command: .removeOneModel(id: "small"),
                              ask: ModelRemoval(alertTitle: "Remove Small?", alertText: "It frees 0.66 GiB. Your tunes stay.", remove: "Remove", cancel: "Cancel",
                                                command: .removeOneModel(id: "small"))),
        ])
        #expect(large.ticked && large.buttons.isEmpty)
    }

    @Test("Small downloading while a tune plays: the bar, the amounts and the speed, Cancel")
    func downloading() throws {
        let c = try models(Fixture.load("52-models-small-downloading"))
        let small = c.rows[0]
        #expect(small.sub == "0.3 of 0.66 GiB · 21 MB/s")
        #expect(abs((small.progress ?? -1) - 314_572_800.0 / 709_846_656) < 1e-9)
        #expect(small.buttons == [ModelsCard.Button(kind: .cancel, control: Control(text: "Cancel", help: "Cancel"), command: .cancelDownload, ask: nil)])
        #expect(buttons(c.rows[1]) == ["Remove"])
    }

    @Test("while a model downloads no other row offers Download")
    func oneAtATime() throws {
        var s = try Fixture.load("49-models-first-64gib")
        s.setup = .downloading
        s.models[1].downloading = true
        s.download = Download(file: 1, files: 4, name: "language model", done: 0, total: 8_128_417_536, rate: 0, error: nil, model: "large")
        let c = try models(s)
        #expect(buttons(c.rows[0]).isEmpty)
        #expect(buttons(c.rows[1]) == ["Cancel"])
    }

    @Test("before any model is on disk each row offers Download")
    func firstRun() throws {
        let c = try models(Fixture.load("48-models-first-16gib"))
        #expect(c.rows.map(\.buttons) == ["small", "large"].map { id in
            [ModelsCard.Button(kind: .download, control: Control(text: "Download", help: "Download \(id == "small" ? "Small" : "Large")"), command: .downloadModel(id: id), ask: nil)]
        })
        #expect(c.rows.map(\.ticked) == [true, false])
        #expect(c.rows.map(\.sub) == ["4.08 GiB to download · about 4 GiB of memory", "7.57 GiB to download · about 8 GiB of memory"])
    }

    @Test("a failed second download: its error and Resume in its row")
    func failed() throws {
        let c = try models(Fixture.load("53-models-second-failed"))
        let small = c.rows[0]
        #expect(small.error == "the connection broke." && small.progress == nil)
        #expect(small.sub == "0.66 GiB to download · about 4 GiB of memory")
        #expect(small.buttons == [ModelsCard.Button(kind: .resume, control: Control(text: "Resume", help: "Resume"), command: .downloadModel(id: "small"), ask: nil)])
        #expect(c.rows[1].error.isEmpty && buttons(c.rows[1]) == ["Remove"])
    }

    @Test("a failed first download of the chosen model resumes as the setup card does")
    func failedFirst() throws {
        var s = try Fixture.load("03-download-failed")
        s.models = try Fixture.load("49-models-first-64gib").models
        s.download?.model = "large"
        let c = try models(s)
        #expect(c.rows[1].buttons.map(\.command) == [.download])
        #expect(!c.rows[1].error.isEmpty)
        #expect(c.rows[0].buttons.map(\.command) == [.downloadModel(id: "small")])
    }
}

@Suite("Music models: what a review settled")
struct ModelsSettledTests {
    /// 03 or 43, a failed first download, with the 64 GiB models (Large
    /// chosen) and the download naming `model`.
    func failedFirst(_ name: String, model: String?) throws -> Snapshot {
        var s = try Fixture.load(name)
        s.models = try Fixture.load("49-models-first-64gib").models
        s.sharedBytes = 3_671_093_888
        s.download?.model = model
        return s
    }

    static let resumes: [(String?, Command)] = [("large", .download), (nil, .download), ("small", .downloadModel(id: "small"))]

    @Test("the setup card's Resume carries on with the model the download was for", arguments: resumes)
    func setupResume(_ model: String?, _ command: Command) throws {
        let c = try setup(failedFirst("03-download-failed", model: model))
        #expect(c.kind == .failed && c.button.text == "Resume" && c.command == command)
    }

    @Test("the stand-in's Resume carries on with the model the download was for", arguments: resumes)
    func standInResume(_ model: String?, _ command: Command) throws {
        let c = try player(failedFirst("43-download-failed-kept", model: model)).composer
        #expect(c.standIn?.button.text == "Resume" && c.standIn?.command == command)
    }

    @Test("a row's Resume carries on with its model", arguments: resumes)
    func rowResume(_ model: String?, _ command: Command) throws {
        let c = try models(failedFirst("03-download-failed", model: model))
        let row = try #require(c.rows.first { !$0.error.isEmpty })
        #expect(row.id == (model ?? "large"))
        #expect(row.buttons.first { $0.kind == .resume }?.command == command)
    }

    func remove(_ r: ModelsCard.Row) -> ModelsCard.Button? { r.buttons.first { $0.kind == .remove } }

    @Test("Large alone while Small downloads: Remove sends removeOneModel, so the engine decides when it is pressed")
    func removeWhileAnotherDownloads() throws {
        let s = try Fixture.load("52-models-small-downloading")
        let b = try #require(remove(try models(s).rows[1]))
        #expect(b.command == .removeOneModel(id: "large"))
        #expect(b.ask?.command == .removeOneModel(id: "large"))
        #expect(b.ask?.alertTitle == "Remove the music model?")
        #expect(b.ask?.alertText == Decide.modelRemoval(s).alertText)
    }

    @Test("no row ever sends removeModel", arguments: ["48-models-first-16gib", "50-models-large-only", "51-models-both-large-chosen",
                                                        "52-models-small-downloading", "53-models-second-failed"])
    func neverRemoveModel(_ name: String) throws {
        let c = try models(Fixture.load(name))
        for r in c.rows {
            for b in r.buttons { #expect(b.command != .removeModel && b.ask?.command != .removeModel) }
            if let b = remove(r) { #expect(b.command == .removeOneModel(id: r.id) && b.ask?.command == b.command) }
        }
    }

    /// Large on disk, a 300,000,000-byte part of Small.
    func smallPart() throws -> Snapshot {
        var s = try Fixture.load("50-models-large-only")
        s.models[0].downloadBytes = 709_846_656 - 300_000_000
        return s
    }

    @Test("a part beside a complete model: how much is downloaded, Resume and Remove")
    func partBeside() throws {
        let row = try models(smallPart()).rows[0]
        #expect(row.sub == "0.28 of 0.66 GiB downloaded" && row.error.isEmpty && row.progress == nil)
        #expect(row.buttons == [
            ModelsCard.Button(kind: .resume, control: Control(text: "Resume", help: "Resume"), command: .downloadModel(id: "small"), ask: nil),
            ModelsCard.Button(kind: .remove, control: Control(text: "Remove", help: "Remove Small"), command: .removeOneModel(id: "small"),
                              ask: ModelRemoval(alertTitle: "Remove Small?", alertText: "It frees 0.28 GiB. Your tunes stay.", remove: "Remove", cancel: "Cancel",
                                                command: .removeOneModel(id: "small"))),
        ])
    }

    @Test("a part with no model complete: how much of that model's download is here, Resume, and Remove as the last model")
    func partAlone() throws {
        var s = try Fixture.load("49-models-first-64gib")
        s.models[1].downloadBytes = 8_128_417_536 - 4_000_000_000
        s.models[0].downloadBytes = 4_380_940_544 - 3_671_093_888
        s.need.onDiskBytes = 4_000_000_000
        let c = try models(s)
        var last = Decide.modelRemoval(s)
        last.command = .removeOneModel(id: "large")
        #expect(c.rows[1].sub == "3.73 of 7.57 GiB downloaded")
        #expect(c.rows[1].buttons == [
            ModelsCard.Button(kind: .resume, control: Control(text: "Resume", help: "Resume"), command: .download, ask: nil),
            ModelsCard.Button(kind: .remove, control: Control(text: "Remove", help: "Remove Large"), command: .removeOneModel(id: "large"), ask: last),
        ])
        #expect(c.rows[0].sub == "3.42 of 4.08 GiB downloaded")
        #expect(c.rows[0].buttons.map(\.command) == [.downloadModel(id: "small"), .removeOneModel(id: "small")])
    }

    @Test("with the shared size unknown and nothing complete, a row says only what is left to download")
    func partUnknown() throws {
        var s = try Fixture.load("49-models-first-64gib")
        s.sharedBytes = 0
        s.models[1].downloadBytes = 8_128_417_536 - 4_000_000_000
        let row = try models(s).rows[1]
        #expect(row.sub == "3.84 GiB to download · about 8 GiB of memory")
        #expect(row.buttons.map(\.kind) == [.download])
    }

    @Test("a part while another model downloads: Remove, no Resume")
    func partWhileFetching() throws {
        var s = try smallPart()
        s.models.append(ModelChoice(id: "medium", name: "Medium", variant: "2B Q8", fileBytes: 2 << 30, downloadBytes: 1 << 30, onDisk: false,
                                    ramBytes: 6 << 30, suggested: false, chosen: false, downloading: true))
        s.download = Download(file: 1, files: 1, name: "language model", done: 1 << 30, total: 2 << 30, rate: 0, error: nil, model: "medium")
        #expect(try models(s).rows[0].buttons.map(\.kind) == [.remove])
    }

    @Test("the footnote names the shared size, and leaves it out when unknown", arguments: [
        (Int64(3_671_093_888), "The models share 3.42 GiB of other files, kept while a model remains. This card is also under Music Models… in the menu bar icon's menu."),
        (2_147_483_648, "The models share 2 GiB of other files, kept while a model remains. This card is also under Music Models… in the menu bar icon's menu."),
        (0, "This card is also under Music Models… in the menu bar icon's menu."),
    ])
    func footnote(_ shared: Int64, _ text: String) throws {
        var s = try Fixture.load("51-models-both-large-chosen")
        s.sharedBytes = shared
        #expect(try models(s).footnote == text)
    }
}

@Suite("Music models: the menu")
struct ModelsMenuTests {
    @Test("Music Models…, always enabled, opens the card", arguments: ["48-models-first-16gib", "50-models-large-only", "52-models-small-downloading"])
    func listed(_ name: String) throws {
        let s = try Fixture.load(name)
        let m = Decide.modelsMenu(s)
        #expect(m.title == "Music Models…" && m.enabled && m.opensCard)
    }

    @Test("with no models listed: Remove Music Model…, as before", arguments: [("44-model-on-disk", true), ("41-no-model-kept", false)])
    func unlisted(_ name: String, _ enabled: Bool) throws {
        let s = try Fixture.load(name)
        #expect(Decide.modelsMenu(s) == ModelsMenu(title: "Remove Music Model…", enabled: enabled, opensCard: false, removal: Decide.modelRemoval(s)))
    }
}

@Suite("Music models: the own-words sheet")
struct ModelsWordsTests {
    func sung(_ name: String) throws -> Snapshot {
        var s = try Fixture.load(name)
        s.genres[4].sung = true
        return s
    }

    func sheet(_ s: Snapshot, _ p: Panel) throws -> WordsCard {
        guard case .words(let c) = card(s, p) else { Issue.record("not the sheet"); throw CancellationError() }
        return c
    }

    @Test("both on disk: the Model row, one capsule per model, starting on the chosen one")
    func both() throws {
        let s = try sung("51-models-both-large-chosen")
        let p = Panel().openingWords(s, name: "Long Way Home")
        let c = try sheet(s, p)
        #expect(c.modelLabel == "Model")
        #expect(c.models == [
            WordsCard.ModelPick(id: "small", control: Control(text: "Small", help: "Small")),
            WordsCard.ModelPick(id: "large", control: Control(lit: true, text: "Large", help: "Large")),
        ])
        #expect(p.wordsModel(s) == "large")
    }

    @Test("a click lights another; Compose passes its id")
    func pick() throws {
        let s = try sung("51-models-both-large-chosen")
        let p = Panel().openingWords(s, name: "Long Way Home").pickingWordsModel("small", in: s)
        #expect(try sheet(s, p).models.map(\.control.lit) == [true, false])
        #expect(p.wordsModel(s) == "small")
        let (sent, words, _) = p.typedWords("[Verse]\nla la", caret: 0).composingWords()
        #expect(words != nil && sent.wordsModel(s) == "small")
    }

    @Test("a model not on disk, an unknown one, or a pick while the request is out: ignored")
    func ignored() throws {
        var s = try sung("51-models-both-large-chosen")
        let p = Panel().openingWords(s, name: "x")
        #expect(p.pickingWordsModel("medium", in: s) == p)
        let (busy, _, _) = p.typedWords("[Verse]\nla", caret: 0).composingWords()
        #expect(busy.pickingWordsModel("small", in: s) == busy)
        s.models[0].onDisk = false
        #expect(p.pickingWordsModel("small", in: s) == p)
    }

    @Test("one model on disk, or none listed: no Model row, Compose passes nil", arguments: ["50-models-large-only", "05-queue-full"])
    func one(_ name: String) throws {
        let s = try sung(name)
        let p = Panel().openingWords(s, name: "x")
        #expect(try sheet(s, p).models.isEmpty)
        #expect(p.wordsModel(s) == nil)
    }

    @Test("the picked model leaves the disk: the row goes, Compose passes nil")
    func leaves() throws {
        var s = try sung("51-models-both-large-chosen")
        let p = Panel().openingWords(s, name: "x").pickingWordsModel("small", in: s)
        s.models[0].onDisk = false
        #expect(try sheet(s, p).models.isEmpty && p.wordsModel(s) == nil)
    }
}

@Suite("Music models: sizes")
struct ModelsFormatTests {
    @Test("two decimals: the Small and Large downloads, the Small file alone", arguments: [
        (Int64(4_380_940_544), "4.08 GiB"), (8_128_417_536, "7.57 GiB"), (709_846_656, "0.66 GiB"), (4_457_323_648, "4.15 GiB"),
    ])
    func gib(_ bytes: Int64, _ text: String) {
        #expect(Format.gib(bytes, decimals: 2) == text)
    }
}
