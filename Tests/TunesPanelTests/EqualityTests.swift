import Foundation
import Testing
import TunesContract
@testable import TunesPanel

/// One change per stored field. The views are redrawn only when their input
/// compares unequal, so a field that equality ignores is a field the screen
/// never updates for. Every stored field of every view-state type is listed;
/// a new field needs a line here.
typealias Change<T> = (field: String, apply: (inout T) -> Void)

func expectEachFieldCounts<T: Equatable>(_ base: T, _ changes: [Change<T>]) {
    for c in changes {
        var v = base
        c.apply(&v)
        #expect(v != base, "\(T.self).\(c.field) is not compared")
    }
}

func flip<T>(_ v: inout T?, _ other: T) { v = v == nil ? other : nil }
func other(_ t: Tone) -> Tone { t == .red ? .green : .red }
func other(_ s: JobStage?) -> JobStage? { s == .writing ? .rendering : .writing }
let anyControl = Control(enabled: false, lit: true, text: "x", help: "y")

@Suite("Every field counts")
struct EqualityTests {
    @Test func control() {
        expectEachFieldCounts(Control(help: "h"), [
            ("enabled", { $0.enabled.toggle() }), ("lit", { $0.lit.toggle() }), ("text", { $0.text += "x" }), ("help", { $0.help += "x" }),
        ] as [Change<Control>])
    }

    @Test func now() throws {
        let base = try player(sungSnapshot()).now
        expectEachFieldCounts(base, [
            ("label", { $0.label += "x" }), ("suffix", { $0.suffix += "x" }), ("genre", { $0.genre.text += "x" }),
            ("title", { $0.title += "x" }), ("titleTone", { $0.titleTone = other($0.titleTone) }),
            ("titleControl", { flip(&$0.titleControl, anyControl) }),
            ("rename", { flip(&$0.rename, PlayerCard.RenameField(text: "a", error: "", save: anyControl, cancel: anyControl)) }),
            ("lyricsButton", { flip(&$0.lyricsButton, anyControl) }), ("lyrics", { flip(&$0.lyrics, "words") }),
            ("lyricsHead", { $0.lyricsHead += "x" }), ("badge", { $0.badge += "x" }), ("meta", { $0.meta += "x" }),
            ("wave", { flip(&$0.wave, PlayerCard.Wave(levels: [], played: 0, help: "")) }),
            ("forming", { $0.forming = other($0.forming) }), ("repeatsOne", { $0.repeatsOne.toggle() }),
            ("time", { flip(&$0.time, PlayerCard.Clock(left: "1", right: "2")) }),
            ("playPause", { $0.playPause.lit.toggle() }), ("showsPause", { $0.showsPause.toggle() }),
            ("previous", { $0.previous.lit.toggle() }), ("previousCommand", { flip(&$0.previousCommand, .next) }), ("next", { $0.next.lit.toggle() }),
            ("shuffle", { $0.shuffle.text += "x" }), ("repeat", { $0.repeat.text += "x" }), ("share", { $0.share.text += "x" }),
            ("scrap", { $0.scrap.text += "x" }),
            ("shareRequest", { flip(&$0.shareRequest, ShareRequest(target: TuneTarget(name: "x", index: 3), file: "f")) }),
            ("scrapCommand", { flip(&$0.scrapCommand, .scrapPlaying(name: "other")) }),
            ("volume", { $0.volume.level -= 0.5 }),
        ] as [Change<PlayerCard.Now>])
    }

    @Test func nowParts() {
        expectEachFieldCounts(PlayerCard.Clock(left: "a", right: "b"), [("left", { $0.left += "x" }), ("right", { $0.right += "x" })] as [Change<PlayerCard.Clock>])
        expectEachFieldCounts(PlayerCard.RenameField(text: "a", error: "", save: anyControl, cancel: anyControl), [
            ("text", { $0.text += "x" }), ("error", { $0.error += "x" }), ("save", { $0.save.lit.toggle() }), ("cancel", { $0.cancel.lit.toggle() }),
        ] as [Change<PlayerCard.RenameField>])
        expectEachFieldCounts(PlayerCard.Wave(levels: [0.5], played: 1, help: "h"), [
            ("levels", { $0.levels.append(1) }), ("played", { $0.played += 1 }), ("help", { $0.help += "x" }),
        ] as [Change<PlayerCard.Wave>])
        expectEachFieldCounts(PlayerCard.Volume(level: 0.5, help: "h"), [
            ("level", { $0.level += 0.01 }), ("help", { $0.help += "x" }),
        ] as [Change<PlayerCard.Volume>])
    }

    @Test func playerCard() throws {
        let base = try player(Fixture.load("06-first-tune"))
        expectEachFieldCounts(base, [
            ("palette", { $0.palette = Palette.made(from: "else") }), ("strip", { flip(&$0.strip, "err") }),
            ("now", { $0.now.title += "x" }), ("next", { $0.next.head += "x" }), ("making", { flip(&$0.making, PlayerCard.Making(head: "", rows: [])) }),
            ("composer", { $0.composer.label += "x" }),
        ] as [Change<PlayerCard>])
        expectEachFieldCounts(base.next, [("label", { $0.label += "x" }), ("head", { $0.head += "x" }), ("rows", { $0.rows.append(base.making!.rows[0]) }), ("playing", { flip(&$0.playing, 7) })] as [Change<PlayerCard.Next>])
        expectEachFieldCounts(try #require(base.making), [("head", { $0.head += "x" }), ("rows", { $0.rows.removeLast() })] as [Change<PlayerCard.Making>])
    }

    @Test func row() throws {
        let base = try player(Fixture.load("05-queue-full")).next.rows[0]
        expectEachFieldCounts(base, [
            ("id", { $0.id += "x" }), ("kind", { $0.kind = .job }), ("index", { flip(&$0.index, 7) }),
            ("state", { $0.state = $0.state == .playing ? .played : .playing }), ("number", { $0.number += "x" }),
            ("name", { $0.name += "x" }), ("nameTone", { $0.nameTone = other($0.nameTone) }), ("tag", { $0.tag += "x" }),
            ("star", { $0.star.toggle() }), ("dim", { $0.dim.toggle() }), ("sub", { $0.sub += "x" }), ("right", { $0.right += "x" }),
            ("rightTone", { $0.rightTone = other($0.rightTone) }), ("bar", { flip(&$0.bar, 0.5) }),
            ("artwork", { flip(&$0.artwork, Artwork.recipe(name: "x", bpm: 1, key: nil, palette: .made(from: "x"))) }),
            ("stage", { $0.stage = other($0.stage) }), ("playNow", { flip(&$0.playNow, anyControl) }), ("share", { flip(&$0.share, anyControl) }),
            ("scrap", { flip(&$0.scrap, anyControl) }), ("playNowCommand", { flip(&$0.playNowCommand, .next) }),
            ("scrapCommand", { flip(&$0.scrapCommand, .scrapJob) }),
            ("shareRequest", { flip(&$0.shareRequest, ShareRequest(target: TuneTarget(name: "x", index: 9), file: "f")) }),
        ] as [Change<PlayerCard.Row>])
    }

    @Test func composer() throws {
        let base = try player(Fixture.load("15-failed-playing")).composer
        let stand = PlayerCard.StandIn(text: "t", detail: "d", progress: nil, button: anyControl, command: .download)
        expectEachFieldCounts(base, [
            ("on", { $0.on.toggle() }), ("label", { $0.label += "x" }), ("labelTone", { $0.labelTone = other($0.labelTone) }),
            ("pill", { flip(&$0.pill, "p") }), ("pillTone", { $0.pillTone = other($0.pillTone) }), ("toggle", { $0.toggle.lit.toggle() }),
            ("lines", { $0.lines.removeLast() }), ("retry", { flip(&$0.retry, anyControl) }), ("words", { flip(&$0.words, anyControl) }),
            ("showsSwitch", { $0.showsSwitch.toggle() }), ("standIn", { flip(&$0.standIn, stand) }),
        ] as [Change<PlayerCard.Composer>])
        expectEachFieldCounts(stand, [
            ("text", { $0.text += "x" }), ("detail", { $0.detail += "x" }), ("progress", { flip(&$0.progress, 0.3) }),
            ("button", { $0.button.lit.toggle() }), ("command", { $0.command = .cancelDownload }),
        ] as [Change<PlayerCard.StandIn>])
        expectEachFieldCounts(base.lines[0], [
            ("pre", { $0.pre += "x" }), ("em", { $0.em += "x" }), ("post", { $0.post += "x" }), ("tone", { $0.tone = other($0.tone) }),
            ("right", { $0.right += "x" }), ("rightTone", { $0.rightTone = other($0.rightTone) }),
        ] as [Change<PlayerCard.Line>])
    }

    @Test func setupCard() throws {
        let base = try TunesPanelTests.setup(Fixture.load("02-downloading"))
        expectEachFieldCounts(base, [
            ("kind", { $0.kind = .failed }), ("title", { $0.title += "x" }), ("detail", { $0.detail += "x" }), ("rows", { $0.rows.removeLast() }),
            ("progress", { flip(&$0.progress, 0.1) }), ("button", { $0.button.lit.toggle() }), ("command", { $0.command = .refresh }),
        ] as [Change<SetupCard>])
        expectEachFieldCounts(base.rows[0], [("label", { $0.label += "x" }), ("value", { $0.value += "x" })] as [Change<SetupCard.Row>])
    }

    @Test func chooserCard() throws {
        let base = try TunesPanelTests.chooser(Fixture.load("05-queue-full"))
        expectEachFieldCounts(base, [
            ("back", { flip(&$0.back, anyControl) }), ("title", { $0.title += "x" }), ("chip", { $0.chip += "x" }), ("cells", { $0.cells.removeLast() }),
            ("add", { $0.add.lit.toggle() }), ("empty", { $0.empty += "x" }), ("strip", { flip(&$0.strip, "e") }),
        ] as [Change<ChooserCard>])
        expectEachFieldCounts(base.cells[0], [
            ("id", { $0.id += "x" }), ("name", { $0.name += "x" }), ("sub", { $0.sub += "x" }), ("current", { $0.current.toggle() }),
            ("pick", { $0.pick.lit.toggle() }), ("edit", { $0.edit.lit.toggle() }),
        ] as [Change<ChooserCard.Cell>])
    }

    @Test func editorCard() throws {
        let s = try Fixture.load("05-queue-full")
        let p = Panel().editingGenre(s.genres[5]).loaded(.success(GenreFields(name: "Classical", caption: "c", turns: [], bpm: [60, 90])), id: "classical", now: NOW)
        let base = try editor(s, p)
        let ask = EditorCard.Ask(title: "t", detail: "d", error: "", keep: anyControl, delete: anyControl)
        expectEachFieldCounts(base, [
            ("back", { $0.back.lit.toggle() }), ("title", { $0.title += "x" }), ("chip", { $0.chip += "x" }), ("values", { $0.values.name += "x" }),
            ("loading", { $0.loading.toggle() }), ("name", { $0.name.error += "x" }), ("caption", { $0.caption.error += "x" }),
            ("turns", { $0.turns.error += "x" }), ("slowest", { $0.slowest.bad.toggle() }), ("fastest", { $0.fastest.bad.toggle() }),
            ("tempoError", { $0.tempoError += "x" }), ("colours", { $0.colours.removeLast() }), ("coloursLabel", { $0.coloursLabel += "x" }),
            ("singing", { $0.singing.on.toggle() }), ("hint", { $0.hint += "x" }), ("delete", { flip(&$0.delete, anyControl) }),
            ("cancel", { $0.cancel.lit.toggle() }), ("save", { $0.save.lit.toggle() }), ("ask", { flip(&$0.ask, ask) }),
        ] as [Change<EditorCard>])
        expectEachFieldCounts(base.name, [
            ("label", { $0.label += "x" }), ("side", { $0.side += "x" }), ("placeholder", { $0.placeholder += "x" }),
            ("error", { $0.error += "x" }), ("bad", { $0.bad.toggle() }),
        ] as [Change<EditorCard.Field>])
        expectEachFieldCounts(ask, [
            ("title", { $0.title += "x" }), ("detail", { $0.detail += "x" }), ("error", { $0.error += "x" }),
            ("keep", { $0.keep.lit.toggle() }), ("delete", { $0.delete.lit.toggle() }),
        ] as [Change<EditorCard.Ask>])
        expectEachFieldCounts(base.singing, [("label", { $0.label += "x" }), ("sub", { $0.sub += "x" }), ("on", { $0.on.toggle() })] as [Change<EditorCard.Singing>])
    }

    @Test func shareCard() throws {
        let s = try Fixture.load("05-queue-full")
        let (p, _) = try openShare(s, index: nil)
        let base = try share(s, p)
        expectEachFieldCounts(base, [
            ("back", { $0.back.lit.toggle() }), ("head", { $0.head += "x" }), ("name", { $0.name += "x" }), ("meta", { $0.meta += "x" }),
            ("hint", { $0.hint += "x" }), ("artwork", { flip(&$0.artwork, Artwork.recipe(name: "x", bpm: nil, key: nil, palette: .made(from: "x"))) }),
            ("file", { flip(&$0.file, URL(fileURLWithPath: "/x")) }), ("rows", { $0.rows.removeLast() }),
        ] as [Change<ShareCard>])
        expectEachFieldCounts(base.rows[4], [
            ("action", { $0.action = .share }), ("title", { $0.title += "x" }), ("sub", { $0.sub += "x" }),
            ("on", { $0.on = $0.on == true ? false : true }), ("control", { $0.control.lit.toggle() }),
        ] as [Change<ShareCard.Row>])
        expectEachFieldCounts(ShareRequest(target: TuneTarget(name: "a", index: nil), file: "f"), [
            ("target", { $0.target.index = 1 }), ("file", { $0.file += "x" }), ("sung", { $0.sung.toggle() }),
        ] as [Change<ShareRequest>])
    }

    @Test func wordsCard() throws {
        let s = try sungSnapshot()
        guard case .words(let base) = card(s, Panel().openingWords(s, name: "n")) else { Issue.record("not the sheet"); return }
        expectEachFieldCounts(base, [
            ("back", { $0.back.lit.toggle() }), ("label", { $0.label += "x" }), ("title", { $0.title += "x" }), ("inserts", { $0.inserts.removeLast() }),
            ("text", { $0.text += "x" }), ("caret", { $0.caret += 1 }), ("counter", { $0.counter += "x" }), ("counterRight", { $0.counterRight += "x" }),
            ("wordsError", { $0.wordsError += "x" }), ("nameLabel", { $0.nameLabel += "x" }), ("name", { $0.name += "x" }),
            ("nameError", { $0.nameError += "x" }), ("note", { $0.note += "x" }), ("refused", { $0.refused += "x" }),
            ("cancel", { $0.cancel.lit.toggle() }), ("compose", { $0.compose.lit.toggle() }),
        ] as [Change<WordsCard>])
    }

    @Test func smallValues() throws {
        expectEachFieldCounts(StatusItem(dim: false, text: "t", dot: nil, help: "h"), [
            ("dim", { $0.dim.toggle() }), ("text", { $0.text += "x" }), ("dot", { flip(&$0.dot, .red) }), ("help", { $0.help += "x" }),
        ] as [Change<StatusItem>])
        let removal = Decide.modelRemoval(try Fixture.load("44-model-on-disk"))
        expectEachFieldCounts(removal, [
            ("menuTitle", { $0.menuTitle += "x" }), ("enabled", { $0.enabled.toggle() }), ("alertTitle", { $0.alertTitle += "x" }),
            ("alertText", { $0.alertText += "x" }), ("remove", { $0.remove += "x" }), ("cancel", { $0.cancel += "x" }), ("command", { $0.command = .refresh }),
        ] as [Change<ModelRemoval>])
        expectEachFieldCounts(Animating(backdrop: false, heroForming: false, jobForming: false, meter: false), [
            ("backdrop", { $0.backdrop.toggle() }), ("heroForming", { $0.heroForming.toggle() }), ("jobForming", { $0.jobForming.toggle() }),
            ("meter", { $0.meter.toggle() }),
        ] as [Change<Animating>])
    }
}

@Suite("What moves")
struct AnimatingTests {
    /// Genre picked with the composer off; composer on and starting; writing.
    func sequence() throws -> [Snapshot] {
        Array(try Fixture.snapshots("20-session")[1...3])
    }

    @Test("genre picked, composer on, starting, writing: the forming wave moves from the first writing snapshot")
    func firstTune() throws {
        let steps = try sequence()
        #expect(steps.map(\.model.state) == [.unloaded, .starting, .writing])
        let p = Panel()
        let heroes = try steps.map { try player($0, p).now }
        #expect(heroes.map(\.forming) == [nil, nil, .writing])
        // The hero's input changes when the job appears, so the view is redrawn.
        #expect(heroes[1] != heroes[2])
        let moves = steps.map { Decide.animating($0, p, now: NOW, popoverOpen: true, reduceMotion: false, lowPower: false) }
        #expect(moves.map(\.heroForming) == [false, false, true])
        #expect(moves.map(\.jobForming) == [false, false, true])
        #expect(moves.map(\.backdrop) == [true, true, true])
    }

    @Test("nothing moves with the popover closed or Reduce Motion on; Low Power stills only the backdrop", arguments: [
        (false, false, false, Animating(backdrop: false, heroForming: false, jobForming: false, meter: false)),
        (true, true, false, Animating(backdrop: false, heroForming: false, jobForming: false, meter: false)),
        (true, false, true, Animating(backdrop: false, heroForming: true, jobForming: true, meter: false)),
        (true, false, false, Animating(backdrop: true, heroForming: true, jobForming: true, meter: false)),
    ])
    func flags(_ open: Bool, _ reduce: Bool, _ lowPower: Bool, _ expected: Animating) throws {
        let writing = try sequence()[2]
        #expect(Decide.animating(writing, Panel(), now: NOW, popoverOpen: open, reduceMotion: reduce, lowPower: lowPower) == expected)
    }

    @Test("a tune playing with a job: the job row's wave moves, the hero shows the tune")
    func tunePlaying() throws {
        let s = try Fixture.load("10-writing")
        let a = Decide.animating(s, Panel(), now: NOW, popoverOpen: true, reduceMotion: false, lowPower: false)
        #expect(!a.heroForming && a.jobForming)
    }
}
