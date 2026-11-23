import Foundation
import Testing
import TunesContract
@testable import TunesPanel

/// The engine's answers in 26-genre-jazz, 27-genre-results and 35-share-lines.
enum Answers {
    static func jazz() throws -> GenreFields {
        let j = try #require(Fixture.json("26-genre-jazz").first)
        return GenreFields(name: j["name"] as! String, caption: j["caption"] as! String, turns: j["turns"] as! [String], bpm: j["bpm"] as! [Int])
    }

    static func refusal(_ j: [String: Any]) -> Refusal {
        Refusal(field: (j["field"] as? String).flatMap(GenreField.init(rawValue:)), text: j["text"] as? String ?? "")
    }

    /// 0: saved with a rename; 1: saved new; 2-5: refusals.
    static func genreResults() throws -> [Result<GenreSaved, Refusal>] {
        try Fixture.json("27-genre-results").map { j in
            if j["ok"] as? Bool == true {
                let r = j["renamed"] as? [String: String]
                return .success(GenreSaved(id: j["id"] as! String, renamed: r.map { Renamed(from: $0["from"]!, to: $0["to"]!) }))
            }
            return .failure(refusal(j))
        }
    }

    static func info(_ j: [String: Any]) -> ShareInfo {
        ShareInfo(name: j["name"] as! String, genre: j["genre"] as! String, bpm: j["bpm"] as? Int, key: j["key"] as? String,
                  length: j["length"] as? Double, bytes: Int64(j["bytes"] as! Int), path: URL(fileURLWithPath: j["path"] as! String),
                  exportPath: URL(fileURLWithPath: j["export_path"] as! String), pinned: j["pinned"] as! Bool)
    }

    static func share() throws -> [[String: Any]] { try Fixture.json("35-share-lines") }
}

@Suite("Chooser")
struct ChooserTests {
    @Test("first open: no genre yet, the chooser whatever the panel's mode")
    func firstOpen() throws {
        let s = try Fixture.load("04-chooser-first")
        let c = try chooser(s, Panel())
        #expect(c.back == nil)
        #expect(c.title == "Genre" && c.chip == "A click plays what is kept")
        #expect(c.cells.prefix(5).map { [$0.name, $0.sub] } == [["Lo-fi", "31 kept"], ["Ambient", "12 kept"], ["Synthwave", "none yet"], ["Deep house", "4 kept"], ["Jazz", "14 kept"]])
        #expect(c.cells.allSatisfy { !$0.current })
        #expect(c.cells[4].pick.help == "Play Jazz" && c.cells[4].edit.help == "Edit Jazz")
        #expect(c.add == Control(text: "+ New genre", help: "Add a genre"))
        #expect(c.empty == "")
        let (p, cmd) = Panel().picking("jazz", in: s)
        #expect(cmd == .selectGenre(id: "jazz") && p.mode == .player)
        let (same, none) = Panel().openingChooser().picking("nope", in: s)
        #expect(none == nil && same.mode == .chooser)
        #expect(!Decide.needsTick(s, Panel(), now: NOW))
    }

    @Test("the selected genre: playing now, paused or selected; picking it again sends nothing", arguments: [
        ("05-queue-full", 4, "playing now"), ("17-paused", 4, "paused"), ("08-nothing-kept", 2, "selected"),
    ])
    func selected(_ name: String, _ index: Int, _ sub: String) throws {
        let s = try Fixture.load(name)
        let c = try chooser(s)
        #expect(c.cells[index].sub == sub && c.cells[index].current)
        #expect(c.cells.filter(\.current).count == 1)
        #expect(c.cells[index].pick.help == "Back to \(c.cells[index].name)")
        #expect(c.back?.text == c.cells[index].name)
        let (p, cmd) = Panel().openingChooser().picking(s.genre!, in: s)
        #expect(cmd == nil && p.mode == .player)
    }

    @Test("a file with no genres: only the + New genre cell, the line over it")
    func noGenres() throws {
        var s = try Fixture.load("04-chooser-first")
        s.genres = []
        let c = try chooser(s)
        #expect(c.empty == "The genres file lists no genres." && c.cells.isEmpty)
        #expect(Panel().addingGenre().mode == .editor)
    }

    @Test("the back link and the genre button")
    func back() throws {
        let s = try Fixture.load("05-queue-full")
        let open = Panel().openingChooser()
        #expect(open.mode == .chooser)
        guard case .player = card(s, open.backToPlayer()) else { Issue.record("not the player"); return }
    }
}

@Suite("Editor")
struct EditorTests {
    func jazzEditor() throws -> (Snapshot, Panel) {
        let s = try Fixture.load("05-queue-full")
        let jazz = try #require(s.genres.first { $0.id == "jazz" })
        return (s, Panel().openingChooser().editingGenre(jazz).loaded(.success(try Answers.jazz()), id: "jazz", now: NOW))
    }

    func errors(_ e: EditorCard) -> [String] { [e.name.error, e.caption.error, e.turns.error, e.tempoError] }

    @Test("editing a genre: empty until its fields come, then filled")
    func load() throws {
        let s = try Fixture.load("05-queue-full")
        let jazz = try #require(s.genres.first { $0.id == "jazz" })
        let waiting = Panel().openingChooser().editingGenre(jazz)
        var e = try editor(s, waiting)
        #expect([e.title, e.chip] == ["Edit Jazz", "14 kept"])
        #expect(e.hint == "Changes apply to the next tune composed. The 14 kept tunes stay as they are.")
        #expect(e.values == GenreFieldsText(name: "", caption: "", turns: "", slowest: "", fastest: ""))
        #expect(e.loading && !e.save.enabled)
        #expect(errors(e) == ["", "", "", ""])
        if case .send = waiting.saving(s) { Issue.record("saved while loading") }
        #expect(waiting.typed(.name, "x") == waiting)
        let filled = waiting.loaded(.success(try Answers.jazz()), id: "jazz", now: NOW)
        e = try editor(s, filled)
        #expect(e.values == GenreFieldsText(
            name: "Jazz",
            caption: "small combo jazz, walking upright bass, brushed snare, warm tenor saxophone lead",
            turns: "smoky club\nlate set, slow and close\nmuted trumpet takes the lead\npiano trio, no horns\nvibraphone solo\nrainy evening\nbossa feel\na slow ballad",
            slowest: "90", fastest: "150"))
        #expect(e.save.enabled)
        #expect([e.name.label, e.caption.label, e.turns.label, e.slowest.label, e.fastest.label] == ["NAME", "PROMPT", "VARIATIONS", "SLOWEST", "FASTEST"])
        #expect([e.caption.side, e.turns.side, e.caption.placeholder, e.turns.placeholder] == ["what every tune has", "one per line, two are picked per tune", "instruments, mood, style, in a few phrases", "one per line"])
        #expect(e.back.text == "Genres" && e.cancel.text == "Cancel" && e.save.text == "Save" && e.delete?.text == "Delete genre…")
        // An answer for another genre, or a second one: nothing changes.
        #expect(waiting.loaded(.success(try Answers.jazz()), id: "lofi", now: NOW) == waiting)
        #expect(filled.loaded(.success(try Answers.jazz()), id: "jazz", now: NOW) == filled)
    }

    @Test("the hint and the chip with one kept tune and with none", arguments: [
        (1, "1 kept", "Changes apply to the next tune composed. The 1 kept tune stays as it is."),
        (0, "none yet", "Changes apply to the next tune composed."),
    ])
    func hint(_ kept: Int, _ chip: String, _ hint: String) throws {
        var (s, p) = try jazzEditor()
        s.genres = s.genres.map { $0.id == "jazz" ? GenreSummary(id: "jazz", name: "Jazz", kept: kept) : $0 }
        let e = try editor(s, p)
        #expect([e.chip, e.hint] == [chip, hint])
    }

    @Test("the genre could not be read: the chooser, the footer says why")
    func gone() throws {
        let s = try Fixture.load("05-queue-full")
        let results = try Answers.genreResults()
        guard case .failure(let r) = results[5] else { Issue.record("fixture"); return }
        let p = Panel().openingChooser().editingGenre(s.genres[4]).loaded(.failure(r), id: "jazz", now: NOW)
        #expect(p.mode == .chooser && p.editor == nil)
        #expect(Decide.footer(s, p, now: NOW) == .notice("That genre no longer exists."))
        let blank = Panel().openingChooser().editingGenre(s.genres[4]).loaded(.failure(Refusal(field: nil, text: "")), id: "jazz", now: NOW)
        #expect(Decide.footer(s, blank, now: NOW) == .notice("That genre could not be read."))
    }

    @Test("a new genre: defaults, errors as typed, Save sends nothing while one stands")
    func newGenre() throws {
        let s = try Fixture.load("05-queue-full")
        var p = Panel().openingChooser().addingGenre()
        var e = try editor(s, p)
        #expect([e.title, e.chip, e.hint] == ["New genre", "", "Tune names come from a shared word list until this genre has its own."])
        #expect(e.values == GenreFieldsText(name: "", caption: "", turns: "", slowest: "70", fastest: "120"))
        #expect(e.turns.side == "optional")
        #expect(e.delete == nil)
        #expect(errors(e) == ["", "", "", ""])
        #expect(!e.name.bad && !e.slowest.bad && !e.fastest.bad)
        #expect(e.save.enabled)
        p = p.typed(.name, "Jazz")
        e = try editor(s, p)
        #expect([e.name.error, e.caption.error] == ["There is already a genre called Jazz.", ""])
        #expect(e.name.bad && !e.save.enabled)
        #expect(try editor(s, p.typed(.name, "jAZZ")).name.error == "There is already a genre called Jazz.")
        guard case .blocked(let tried) = p.saving(s) else { Issue.record("sent with an error"); return }
        #expect(errors(try editor(s, tried)) == ["There is already a genre called Jazz.", "A genre needs a prompt.", "", ""])
        let fixed = tried.typed(.name, "  Bossa nova ").typed(.caption, " nylon guitar, soft shaker ").typed(.turns, "beach at dusk\n\n  beach at dusk \nslow samba")
        #expect(errors(try editor(s, fixed)) == ["", "", "", ""])
        guard case .send(let sent, let id, let fields, let base) = fixed.saving(s) else { Issue.record("not sent"); return }
        #expect(id == nil && base == nil)
        #expect(fields == GenreFields(name: "  Bossa nova ", caption: " nylon guitar, soft shaker ", turns: ["beach at dusk", "", "  beach at dusk ", "slow samba"], bpm: [70, 120]))
        #expect(!(try editor(s, sent)).save.enabled)
        if case .send = sent.saving(s) { Issue.record("sent twice") }
        let results = try Answers.genreResults()
        let done = sent.saved(results[1], id: nil, now: NOW)
        #expect(done.mode == .chooser && done.editor == nil && done.notice == nil)
    }

    @Test("an empty name shows once typed in and cleared, not before")
    func untouched() throws {
        let s = try Fixture.load("05-queue-full")
        let p = Panel().addingGenre()
        #expect(try editor(s, p.typed(.name, "x")).name.error == "")
        #expect(try editor(s, p.typed(.name, "x").typed(.name, "")).name.error == "A genre needs a name.")
    }

    @Test("tempo errors under the row, the boxes they are about in red", arguments: [
        ("130", "120", "The slowest tempo is above the fastest.", true, true),
        ("70", "301", "Tempos go from 30 to 300 BPM.", false, true),
        ("29", "120", "Tempos go from 30 to 300 BPM.", true, false),
        ("20", "400", "Tempos go from 30 to 300 BPM.", true, true),
        ("", "120", "The slowest tempo needs a whole number.", true, false),
        ("70", "fast", "The fastest tempo needs a whole number.", false, true),
        ("", "", "The slowest tempo needs a whole number.", true, true),
        (" 090 ", "150", "", false, false),
    ])
    func tempo(_ lo: String, _ hi: String, _ error: String, _ loBad: Bool, _ hiBad: Bool) throws {
        let s = try Fixture.load("05-queue-full")
        let e = try editor(s, Panel().addingGenre().typed(.slowest, lo).typed(.fastest, hi))
        #expect(e.tempoError == error)
        #expect(e.slowest.bad == loBad && e.fastest.bad == hiBad)
    }

    @Test("each box shows its own rule's error, whatever the others hold")
    func perField() throws {
        let s = try Fixture.load("05-queue-full")
        let long = String(repeating: "a", count: 121)
        let p = Panel().addingGenre().typed(.name, "AC/DC").typed(.caption, "  ").typed(.turns, "one\n\n\(long)").typed(.fastest, "20")
        let e = try editor(s, p)
        #expect(errors(e) == ["A name cannot contain a slash: it is also a folder's name.", "A genre needs a prompt.", "Line 3 is longer than 120 characters.", "Tempos go from 30 to 300 BPM."])
        #expect(try editor(s, Panel().addingGenre().typed(.name, "exPorts")).name.error == "Exports is the folder for exported copies; pick another name.")
    }

    @Test("saving an edit: the base goes back; a rename says so in the footer for 6 s")
    func rename() throws {
        let (s, p) = try jazzEditor()
        guard case .send(let sent, let id, let fields, let base) = p.typed(.name, "Bebop").saving(s) else { Issue.record("not sent"); return }
        let jazz = try Answers.jazz()
        #expect(id == "jazz" && base == jazz)
        #expect(fields == GenreFields(name: "Bebop", caption: jazz.caption, turns: jazz.turns, bpm: [90, 150]))
        let done = sent.saved(try Answers.genreResults()[0], id: "jazz", now: NOW)
        #expect(done.mode == .chooser)
        let after = try Fixture.load("29-after-save")
        #expect(Decide.footer(after, done, now: NOW) == .notice("Renamed Jazz to Bebop. Its folder in ~/Music/Tunes moved with it."))
        #expect(Decide.needsTick(after, done, now: NOW))
        #expect(Decide.footer(after, done, now: NOW + 6) == nil)
        #expect(!Decide.needsTick(after, done, now: NOW + 6))
        // A save answered for another editor than the open one changes nothing.
        #expect(sent.saved(try Answers.genreResults()[1], id: nil, now: NOW) == sent)
    }

    @Test("a refusal naming a box: under it, Save off until that box changes")
    func refusedName() throws {
        let (s, p) = try jazzEditor()
        guard case .send(let sent, _, _, _) = p.typed(.name, "Bebop").saving(s) else { Issue.record("not sent"); return }
        let refused = sent.saved(try Answers.genreResults()[2], id: "jazz", now: NOW)
        var e = try editor(s, refused)
        #expect(refused.mode == .editor)
        #expect(e.name.error == "A folder called Bebop is already in ~/Music/Tunes." && e.name.bad && e.tempoError == "")
        #expect(!e.save.enabled)
        if case .send = refused.saving(s) { Issue.record("sent over a refusal") }
        #expect(try editor(s, refused.typed(.caption, "other")).name.error == "A folder called Bebop is already in ~/Music/Tunes.")
        let renamed = refused.typed(.name, "Hard bop")
        e = try editor(s, renamed)
        #expect(e.name.error == "" && e.save.enabled)
        #expect(try editor(s, refused.typed(.caption, "x").typed(.name, "Lo-fi")).name.error == "There is already a genre called Lo-fi.")
    }

    @Test("a refusal naming no box: under the tempo row; Save may try again; any change clears it")
    func refusedFile() throws {
        let (s, p) = try jazzEditor()
        guard case .send(let sent, _, _, _) = p.saving(s) else { Issue.record("not sent"); return }
        let refused = sent.saved(try Answers.genreResults()[3], id: "jazz", now: NOW)
        let e = try editor(s, refused)
        #expect(e.tempoError == "The genres file on disk is broken: line 4: expected a comma.")
        #expect(e.slowest.bad && e.fastest.bad && e.name.error == "")
        #expect(e.save.enabled)
        #expect(try editor(s, refused.typed(.turns, "one")).tempoError == "")
        let bpm = sent.saved(try Answers.genreResults()[4], id: "jazz", now: NOW)
        #expect(try editor(s, bpm).tempoError == "The tempo range is not valid.")
        #expect(try editor(s, bpm.typed(.name, "Cool jazz")).tempoError == "The tempo range is not valid.")
        #expect(try editor(s, bpm.typed(.fastest, "149")).tempoError == "")
        let blank = sent.saved(.failure(Refusal(field: nil, text: "")), id: "jazz", now: NOW)
        #expect(try editor(s, blank).tempoError == "The genre was not saved.")
    }

    @Test("Cancel: nothing saved, the chooser")
    func cancel() throws {
        let (_, p) = try jazzEditor()
        let back = p.typed(.name, "Changed").discardingEdit()
        #expect(back.mode == .chooser && back.editor == nil)
        #expect(back.typed(.name, "x") == back)
    }

    @Test("deleting a genre: the question, its words, Keep it, Delete")
    func delete() throws {
        let s = try Fixture.load("05-queue-full")
        let classical = s.genres[5]
        let open = Panel().openingChooser().editingGenre(classical).loaded(.success(GenreFields(name: "Classical", caption: "c", turns: [], bpm: [60, 90])), id: "classical", now: NOW)
        let asking = open.askingDelete()
        let ask = try #require(try editor(s, asking).ask)
        #expect([ask.title, ask.detail, ask.error] == ["Delete Classical?", "Its 9 kept tunes stay in ~/Music/Tunes/Classical. Only the genre leaves the panel.", ""])
        #expect([ask.keep.text, ask.delete.text] == ["Keep it", "Delete Classical"])
        #expect(asking.keepingGenre().editor?.asking == false)
        let (sent, id) = asking.deleting()
        #expect(id == "classical")
        #expect(sent.deleting().id == nil)
        #expect(sent.deleted(.success(()), id: "classical").mode == .chooser)
        let no = sent.deleted(.failure(Refusal(field: nil, text: "The last genre cannot be deleted.")), id: "classical")
        #expect(try editor(s, no).ask?.error == "The last genre cannot be deleted.")
        #expect(no.deleting().id == "classical")
        #expect(try editor(s, no.deleting().0).ask?.error == "")
        #expect(try editor(s, sent.deleted(.failure(Refusal(field: nil, text: "")), id: "classical")).ask?.error == "The genre was not deleted.")
    }

    @Test("the delete question's words by kept count", arguments: [
        (0, "Only the genre leaves the panel."),
        (1, "Its 1 kept tune stays in ~/Music/Tunes/Classical. Only the genre leaves the panel."),
    ])
    func deleteWords(_ kept: Int, _ detail: String) throws {
        var s = try Fixture.load("05-queue-full")
        s.genres[5].kept = kept
        let p = Panel().editingGenre(s.genres[5]).loaded(.success(GenreFields(name: "Classical", caption: "c", turns: [], bpm: [60, 90])), id: "classical", now: NOW).askingDelete()
        #expect(try editor(s, p).ask?.detail == detail)
    }

    @Test("the last genre cannot be deleted: no Delete genre…")
    func lastGenre() throws {
        let s = try Fixture.load("28-one-genre")
        let p = Panel().editingGenre(s.genres[0]).loaded(.success(GenreFields(name: s.genres[0].name, caption: "c", turns: [], bpm: [60, 90])), id: s.genres[0].id, now: NOW)
        #expect(try editor(s, p).delete == nil)
    }

    @Test("outside text in the editor and the delete question passes through")
    func outsideText() throws {
        var s = try Fixture.load("05-queue-full")
        s.genres = [GenreSummary(id: "x", name: "<i>X & co", kept: 2), GenreSummary(id: "y", name: "Y", kept: 0)]
        let p = Panel().editingGenre(s.genres[0]).loaded(.success(GenreFields(name: "<i>X & co", caption: "c", turns: [], bpm: [60, 90])), id: "x", now: NOW)
        #expect(try editor(s, p).title == "Edit <i>X & co")
        let ask = try #require(try editor(s, p.askingDelete()).ask)
        #expect([ask.title, ask.detail] == ["Delete <i>X & co?", "Its 2 kept tunes stay in ~/Music/Tunes/<i>X & co. Only the genre leaves the panel."])
        #expect(try editor(s, Panel().addingGenre().typed(.name, "<I>x & CO")).name.error == "There is already a genre called <i>X & co.")
    }
}

@Suite("Modes")
struct ModeTests {
    @Test("shuffle and repeat: lit while on, the repeat control names the mode it switches to", arguments: [
        ("30-modes-default", true, true, "all", "Repeat one", true, Command.setShuffle(on: false), Command.setRepeat(.one)),
        ("31-shuffle-off", false, true, "all", "Repeat one", true, .setShuffle(on: true), .setRepeat(.one)),
        ("32-repeat-one", true, true, "one", "Repeat off", true, .setShuffle(on: false), .setRepeat(.off)),
        ("33-ended", true, false, "off", "Repeat all", false, .setShuffle(on: false), .setRepeat(.all)),
    ])
    func pills(_ name: String, _ shuffle: Bool, _ repeatLit: Bool, _ mode: String, _ help: String, _ canShare: Bool, _ s: Command, _ r: Command) throws {
        let snap = try Fixture.load(name)
        let n = try player(snap).now
        #expect(n.shuffle.lit == shuffle && n.shuffle.help == "Shuffle")
        #expect(n.repeat.lit == repeatLit && n.repeat.text == mode && n.repeat.help == help)
        #expect(n.share.enabled == canShare)
        #expect(Actions.shuffle(snap) == s && Actions.repeat(snap) == r)
    }

    struct Combo: Sendable, CustomTestStringConvertible {
        var shuffle: Bool
        var mode: RepeatMode
        var composing: Bool
        var fresh: Bool
        var ended: Bool
        var testDescription: String { "shuffle \(shuffle) repeat \(mode) composing \(composing) new \(fresh) ended \(ended)" }
    }

    // A round ends only with nothing new ready, and only under repeat off.
    static let combos: [Combo] = [true, false].flatMap { sh in
        [RepeatMode.all, .one, .off].flatMap { m in
            [true, false].flatMap { c in
                [true, false].flatMap { f in
                    [true, false].compactMap { e in e && (f || m != .off) ? nil : Combo(shuffle: sh, mode: m, composing: c, fresh: f, ended: e) }
                }
            }
        }
    }

    @Test("every heading and wording across shuffle, repeat, composer, new tunes ready and ended", arguments: combos)
    func headings(_ c: Combo) throws {
        #expect(Self.combos.count == 2 * 3 * 2 * 2 + 2 * 2)
        let base = try Fixture.load("31-shuffle-off")
        let fresh = QueuedTune(name: "Neon Harbour", file: "20261123-080000-104bpm-A-minor", bpm: 104, key: "A minor", length: 175.6, kept: false, new: true, pinned: false, pos: nil)
        var kept = base.queue
        if c.shuffle {
            kept = [base.queue[0]]
            kept[0].pos = nil
        }
        var s = base
        s.shuffle = c.shuffle
        s.repeat = c.mode
        s.composing = c.composing
        s.ended = c.ended
        s.queue = c.ended ? [] : (c.fresh ? [fresh] : []) + kept
        s.ready = c.fresh ? 1 : 0
        s.keptPlaying = !c.fresh && !c.ended
        s.tune = c.ended ? nil : base.tune
        s.player = c.ended ? .none : .playing
        s.canNext = !c.ended
        s.model.state = c.composing ? .idle : .unloaded
        let p = try player(s)
        #expect(p.now.suffix == (c.ended ? "" : c.mode == .one ? "repeating" : "kept tunes"))
        let head: String
        if c.ended {
            head = c.composing ? "0 ready" : "nothing"
        } else if c.mode == .one {
            head = "after the repeat"
        } else if c.fresh {
            head = "1 ready"
        } else {
            head = c.shuffle ? "from 14 kept, shuffled" : "4 of 14, in the order made"
        }
        #expect(p.next.head == head)
        let tunes = p.next.rows.filter { $0.kind == .tune }
        #expect(tunes.allSatisfy { $0.dim == (c.mode == .one) })
        #expect(tunes.map(\.tag) == s.queue.map { $0.new ? "new" : "" })
        #expect(tunes.map(\.number) == (c.ended ? [] : (c.fresh ? [""] : []) + (c.shuffle ? ["1"] : ["5", "6", "7"])))
        #expect(lines(p).filter { $0.contains("until the repeat ends") } == (c.mode == .one && c.fresh ? ["1 new tune waits until the repeat ends."] : []))
        #expect([p.now.title, p.now.meta] == (c.ended ? ["Played all 14 Jazz tunes", "Play starts over. Repeat is off."] : ["Lazy Avenue", "139 BPM · C major"]))
        #expect(p.now.playPause.help == (c.ended ? "Play" : "Pause"))
        #expect(p.now.share.enabled == !c.ended)
    }

    @Test("two new tunes waiting behind the repeat: the plural")
    func twoWaiting() throws {
        let p = try player(Fixture.load("32-repeat-one"))
        #expect(lines(p) == ["Makes Jazz, keeps 2 ahead | resting, queue is full", "2 new tunes wait until the repeat ends."])
        #expect(rows(p) == [["", "Neon Harbour", "104 BPM · A minor", "2:55"], ["", "Slow Signal", "118 BPM · E minor", "2:50"]])
    }

    @Test("repeat off at the end of the round: the ended state")
    func ended() throws {
        let s = try Fixture.load("33-ended")
        let p = try player(s)
        #expect([p.now.title, p.now.meta] == ["Played all 14 Jazz tunes", "Play starts over. Repeat is off."])
        #expect(p.now.titleTone == .soft && !p.now.showsPause && p.now.playPause.enabled && !p.now.next.enabled)
        #expect(p.now.wave == nil && p.now.time == nil && !p.now.scrap.enabled)
        #expect(p.next.head == "nothing" && p.next.rows.isEmpty)
        #expect(Decide.statusItem(s) == StatusItem(dim: true, text: "", dot: nil, help: "SwiftTunes"))
        #expect(!Decide.needsTick(s, Panel(), now: NOW))
        var one = s
        one.keptTotal = 1
        one.genres[4].kept = 1
        #expect(try player(one).now.title == "Played all 1 Jazz tune")
    }

    @Test("kept for good: the badge and the queue row's star; shuffle off numbers kept rows by their place")
    func pinned() throws {
        let p = try player(Fixture.load("34-pinned"))
        #expect(p.now.badge == "★ kept for good")
        #expect(p.next.rows.map { "\($0.name) \($0.star) \($0.tag) \($0.dim)" } == ["Brass Lantern true  false"])
        let plain = try player(Fixture.load("30-modes-default"))
        #expect(plain.now.badge == "" && plain.next.rows.map(\.star) == [false])
        #expect(try rows(player(Fixture.load("31-shuffle-off"))).map { [$0[0], $0[1]] } == [["5", "Brass Lantern"], ["6", "Quiet Ledger"], ["7", "Late Tram"]])
    }
}

@Suite("Share sheet")
struct ShareTests {
    func described(_ name: String = "30-modes-default", index: Int? = nil, line: Int = 0) throws -> (Snapshot, Panel) {
        let s = try Fixture.load(name)
        let (p, target) = try openShare(s, index: index)
        let t = try #require(target)
        return (s, p.described(.success(Answers.info(try Answers.share()[line])), target: t, now: NOW))
    }

    @Test("the share control on the playing tune: the sheet, waiting for its description")
    func open() throws {
        let s = try Fixture.load("30-modes-default")
        let (p, target) = try openShare(s, index: nil)
        #expect(target == TuneTarget(name: "Lazy Avenue", index: nil))
        let c = try share(s, p)
        #expect([c.head, c.name, c.meta] == ["Jazz", "Lazy Avenue", ""])
        #expect(c.rows.map(\.title) == ["Copy the file", "Copy its path", "Show it in Finder", "Export a copy", "Keep it for good"])
        #expect(c.rows.allSatisfy { !$0.control.enabled })
        #expect(c.back.text == "Back")
        #expect(try openShare(Fixture.load("06-first-tune"), index: nil).1 == nil)
        #expect(try openShare(s, index: 3).1 == nil)
    }

    @Test("described: the meta line, the paths with ~, the rule, the switch")
    func rows() throws {
        let (s, p) = try described()
        let c = try share(s, p)
        #expect(c.meta == "139 BPM · C major · 2:57 · AAC, 4.1 MB")
        #expect(c.rows.map(\.sub) == [
            "paste it into a chat, a mail or a folder",
            "~/Music/Tunes/Jazz/20261123-070612-139bpm-C-major.m4a",
            "",
            "to ~/Music/Tunes/Exports/Jazz - Lazy Avenue.m4a",
            "never removed by the newest-50 rule",
        ])
        #expect(c.rows.map(\.on) == [nil, nil, nil, nil, false])
        #expect(c.rows.allSatisfy { $0.control.enabled })
        #expect(c.rows.map(\.control.help) == ["Copy the file", "Copy its path", "Show it in Finder", "Export a copy", "Keep it for good"])
    }

    @Test("an answer for another tune, or a second one, changes nothing")
    func notCrossed() throws {
        let s = try Fixture.load("30-modes-default")
        let (p, _) = try openShare(s, index: nil)
        let other = p.described(.success(Answers.info(try Answers.share()[5])), target: TuneTarget(name: "Brass Lantern", index: 0), now: NOW)
        #expect(other == p)
        let (_, done) = try described()
        #expect(done.described(.success(Answers.info(try Answers.share()[5])), target: TuneTarget(name: "Lazy Avenue", index: nil), now: NOW) == done)
    }

    @Test("a refusal of the description closes the sheet with its words")
    func refused() throws {
        let s = try Fixture.load("30-modes-default")
        let (p, t) = try openShare(s, index: nil)
        let closed = p.described(.failure(Refusal(field: nil, text: "That tune is no longer there.")), target: t!, now: NOW)
        #expect(closed.mode == .player)
        #expect(Decide.footer(s, closed, now: NOW) == .notice("That tune is no longer there."))
    }

    @Test("a queue row's share: the row's tune, by index")
    func row() throws {
        let (s, p) = try described("34-pinned", index: 0, line: 5)
        #expect(p.share?.target == TuneTarget(name: "Brass Lantern", index: 0))
        let c = try share(s, p)
        #expect(c.name == "Brass Lantern")
        #expect(c.rows[4].on == true && c.rows[4].control.lit)
    }

    @Test("export and keep for good: where the tune is now", arguments: [0, 1, 2])
    func targetNow(_ where_: Int) throws {
        let (s0, p) = try described("34-pinned", index: 0, line: 5)
        var s = s0
        let expected: TuneTarget
        switch where_ {
        case 0:
            s.queue.insert(QueuedTune(name: "New One", file: "f", bpm: nil, key: nil, length: nil, kept: false, new: true, pinned: false, pos: nil), at: 0)
            expected = TuneTarget(name: "Brass Lantern", index: 1)
        case 1:
            let q = s.queue[0]
            s.queue = []
            s.tune = PlayingTune(name: q.name, file: q.file, bpm: q.bpm, key: q.key, length: q.length, kept: q.kept, new: q.new, pinned: q.pinned, pos: q.pos, wave: [])
            expected = TuneTarget(name: "Brass Lantern", index: nil)
        default:
            s.queue = []
            expected = TuneTarget(name: s0.queue[0].file, index: nil)
        }
        let (busy, t) = p.sharing(s)
        #expect(t == expected)
        #expect(busy.sharing(s).1 == nil)
        #expect(!(try share(s, busy)).rows[3].control.enabled)
    }

    @Test("nothing acts before the tune is described")
    func notYet() throws {
        let s = try Fixture.load("30-modes-default")
        let (p, _) = try openShare(s, index: nil)
        #expect(p.sharing(s).1 == nil)
        #expect(p.didFileAction(.copyFile, done: true, now: NOW) == p)
    }

    @Test("each result closes the sheet with its line in the footer")
    func results() throws {
        let (s, p) = try described()
        let lines = try Answers.share()
        let (busy, _) = p.sharing(s)
        let export = busy.exported(.success(URL(fileURLWithPath: lines[1]["path"] as! String)), home: HOME, now: NOW)
        #expect(Decide.footer(s, export, now: NOW) == .notice("Exported Lazy Avenue to ~/Music/Tunes/Exports."))
        #expect(Decide.footer(s, busy.pinned(.success(PinResult(on: true, name: "Lazy Avenue")), now: NOW), now: NOW) == .notice("Lazy Avenue is kept for good."))
        #expect(Decide.footer(s, busy.pinned(.success(PinResult(on: false, name: "Lazy Avenue")), now: NOW), now: NOW) == .notice("Lazy Avenue is no longer kept for good."))
        #expect(Decide.footer(s, busy.exported(.failure(Answers.refusal(lines[4])), home: HOME, now: NOW), now: NOW) == .notice("Lazy Avenue is no longer there."))
        #expect(p.exported(.success(URL(fileURLWithPath: "/x/y")), home: HOME, now: NOW) == p)
        for (action, text) in [(Panel.FileAction.copyFile, "Copied Lazy Avenue as a file. Paste it anywhere."), (.copyPath, "Copied the path of Lazy Avenue."), (.showInFinder, "Showed Lazy Avenue in Finder.")] {
            let done = p.didFileAction(action, done: true, now: NOW)
            #expect(done.mode == .player && done.share == nil)
            #expect(Decide.footer(s, done, now: NOW) == .notice(text))
            #expect(Decide.needsTick(s, done, now: NOW))
        }
    }

    @Test("a file action the system did not do: the sheet closes with no line", arguments: [Panel.FileAction.copyFile, .copyPath, .showInFinder])
    func fileActionFailed(_ action: Panel.FileAction) throws {
        let (s, p) = try described()
        let closed = p.didFileAction(action, done: false, now: NOW)
        #expect(closed.mode == .player && closed.share == nil && closed.notice == nil)
        #expect(Decide.footer(s, closed, now: NOW) == nil)
    }

    @Test("a notice in the player shows in place of the undo line, then the undo line again")
    func noticeOverUndo() throws {
        let s = try Fixture.load("11-after-scrap")
        let (p, t) = try openShare(s, index: nil)
        let closed = p.described(.failure(Refusal(field: nil, text: "That tune is no longer there.")), target: t!, now: NOW - 1)
        #expect(Decide.footer(s, closed, now: NOW) == .notice("That tune is no longer there."))
        #expect(Decide.footer(s, closed, now: NOW + 5) == .undo(text: "Scrapped Lazy Avenue.", button: Control(text: "Undo · 5 s", help: "Undo")))
    }
}

@Suite("Esc")
struct EscapeTests {
    @Test("the player and the setup cards close the popover", arguments: ["05-queue-full", "01-not-set-up", "02-downloading", "03-download-failed"])
    func closes(_ name: String) throws {
        let (p, close) = Panel().escaping(try Fixture.load(name))
        #expect(close && p == Panel())
    }

    @Test("the chooser goes back to the player, or closes with no genre picked")
    func chooser() throws {
        let (back, close) = Panel().openingChooser().escaping(try Fixture.load("05-queue-full"))
        #expect(!close && back.mode == .player)
        #expect(Panel().openingChooser().escaping(try Fixture.load("04-chooser-first")).close)
    }

    @Test("the share sheet goes back to the player")
    func shareSheet() throws {
        let s = try Fixture.load("30-modes-default")
        let (p, _) = try openShare(s, index: nil)
        let (back, close) = p.escaping(s)
        #expect(!close && back.mode == .player && back.share == nil)
    }

    @Test("the editor discards; its delete question keeps the genre")
    func editor() throws {
        let s = try Fixture.load("05-queue-full")
        let edit = Panel().openingChooser().editingGenre(s.genres[5])
            .loaded(.success(GenreFields(name: "Classical", caption: "c", turns: [], bpm: [60, 90])), id: "classical", now: NOW)
        let (discarded, c1) = edit.typed(.name, "Changed").escaping(s)
        #expect(!c1 && discarded.mode == .chooser && discarded.editor == nil)
        let (kept, c2) = edit.askingDelete().escaping(s)
        #expect(!c2 && kept.mode == .editor && kept.editor?.asking == false)
        let (stays, c3) = edit.askingDelete().deleting().0.escaping(s)
        #expect(!c3 && stays.editor?.busy == true && stays.editor?.asking == true)
    }
}
