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

    @Test("with no models listed: the variant on the model line and no capsule", arguments: Fixture.states.filter { !$0.contains("-models-") })
    func noModels(_ name: String) throws {
        let s = try Fixture.load(name)
        guard case .player(let p) = card(s) else { return }
        #expect(capsules(p).isEmpty)
    }
}

@Suite("Music models: the card")
struct ModelsCardTests {
    let header = ("MUSIC MODELS", "Music models", "New tunes are made with the ticked one. A change applies from the next tune.",
                  "Both share 3.42 GiB of other files, kept while a model remains. This card is also under Music Models… in the menu bar icon's menu.")

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
        #expect(large.buttons == [ModelsCard.Button(kind: .remove, control: Control(text: "Remove", help: "Remove Large"), command: .removeModel, ask: Decide.modelRemoval(s))])
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
