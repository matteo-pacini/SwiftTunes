import Testing
import TunesContract
@testable import TunesPanel

/// Jazz made sung, with the playing tune and the first queued one sung.
func sungSnapshot() throws -> Snapshot {
    var s = try Fixture.load("05-queue-full")
    s.genres[4].sung = true
    s.tune?.sung = true
    s.tune?.lyrics = "[Verse]\nNeon lights and midnight streets\n<b>not bold</b>"
    s.queue[0].sung = true
    return s
}

@Suite("Singing")
struct SingingTests {
    @Test("sung joins the tempo and key wherever they show")
    func meta() throws {
        let s = try sungSnapshot()
        let p = try player(s)
        #expect(p.now.meta == "139 BPM · C major · sung")
        #expect(p.next.rows.map(\.sub) == ["139 BPM · C major · sung", "112 BPM · F major · sung", "96 BPM · D minor"])
        var paused = s
        paused.player = .paused
        #expect(try player(paused).now.meta == "139 BPM · C major · sung · paused")
        let (sheet, _) = try openShare(s, index: nil)
        #expect(sheet.share?.sung == true)
        let info = ShareInfo(name: "Lazy Avenue", genre: "Jazz", bpm: 139, key: "C major", length: 177, bytes: 5_700_000,
                             path: .init(fileURLWithPath: "/x.m4a"), exportPath: .init(fileURLWithPath: "/y.m4a"), pinned: false)
        let described = sheet.described(.success(info), target: TuneTarget(name: "Lazy Avenue", index: nil), now: NOW)
        #expect(try share(s, described).meta == "139 BPM · C major · sung · 2:57 · AAC, 5.7 MB")
    }

    @Test("the Lyrics button only on a sung playing tune; open, the words as written")
    func lyrics() throws {
        let s = try sungSnapshot()
        let closed = try player(s).now
        #expect(closed.lyricsButton == Control(text: "Lyrics", help: "Lyrics") && closed.lyrics == nil)
        let open = Panel().togglingLyrics(s)
        let now = try player(s, open).now
        #expect(now.lyricsButton?.lit == true)
        #expect(now.lyrics == "[Verse]\nNeon lights and midnight streets\n<b>not bold</b>")
        #expect(now.lyricsHead == "LYRICS AS WRITTEN")
        #expect(open.togglingLyrics(s).lyricsOf == nil)
        #expect(try player(Fixture.load("05-queue-full")).now.lyricsButton == nil)
        #expect(Panel().togglingLyrics(try Fixture.load("05-queue-full")).lyricsOf == nil)
    }

    @Test("the words close when another tune plays")
    func lyricsFollow() throws {
        let s = try sungSnapshot()
        let open = Panel().togglingLyrics(s)
        var next = s
        next.tune = PlayingTune(name: "Brass Lantern", file: s.queue[0].file, bpm: 112, key: "F major", length: 174.3, kept: false, new: true, pinned: false, pos: nil, wave: [], sung: true, lyrics: "x")
        #expect(open.following(next).lyricsOf == nil)
        #expect(try player(next, open).now.lyrics == nil)
        #expect(open.following(s) == open)
    }

    @Test("the editor's Singing row, and the hint when the switch differs from the saved value", arguments: [
        (false, false, "Changes apply to the next tune composed. The 14 kept tunes stay as they are."),
        (false, true, "Tunes already kept stay as they are; new ones will be sung."),
        (true, false, "Tunes already kept stay as they are; new ones will be instrumental."),
        (true, true, "Changes apply to the next tune composed. The 14 kept tunes stay as they are."),
    ])
    func editorRow(_ saved: Bool, _ now: Bool, _ hint: String) throws {
        let s = try Fixture.load("05-queue-full")
        var p = Panel().editingGenre(s.genres[4])
            .loaded(.success(GenreFields(name: "Jazz", caption: "c", turns: [], bpm: [80, 120], sung: saved)), id: "jazz", now: NOW)
        if saved != now { p = p.togglingSung() }
        let e = try editor(s, p)
        #expect(e.singing == EditorCard.Singing(label: "Singing", sub: "The model writes the words, in English. Say what the voice is like in the prompt.", on: now))
        #expect(e.hint == hint)
        guard case .send(_, _, let fields, _) = p.saving(s) else { Issue.record("not sent"); return }
        #expect(fields.sung == now)
    }

    @Test("a new genre starts instrumental, with its own hint")
    func newGenre() throws {
        let s = try Fixture.load("05-queue-full")
        let e = try editor(s, Panel().addingGenre().togglingSung())
        #expect(e.singing.on)
        #expect(e.hint == "Tune names come from a shared word list until this genre has its own.")
    }

    @Test("writing again for thin words, and the failure after the third plan")
    func composer() throws {
        var s = try Fixture.load("10-writing")
        s.model.thinWords = true
        #expect(lines(try player(s)).contains("Writing again: the last plan had too few sung lines."))
        s.model.state = .failed
        s.model.detail = "3 plans in a row had too few sung lines"
        s.model.failures = 1
        s.model.retryAt = nil
        #expect(lines(try player(s)).contains("Failed: 3 plans in a row had too few sung lines. 1 failure in a row."))
    }

    @Test("Sing my words… on a sung genre's composer bar, on or off; off while one is being made")
    func wordsControl() throws {
        var s = try sungSnapshot()
        #expect(try player(s).composer.words == Control(text: "Sing my words…", help: "Sing my words…"))
        s.composing = false
        #expect(try player(s).composer.words?.enabled == true)
        s.job = Job(stage: .writing, started: NOW - 9, expectS: nil, writtenS: nil, sung: true, ownWords: true, name: "Long Way Home")
        #expect(try player(s).composer.words?.enabled == false)
        #expect(try player(Fixture.load("05-queue-full")).composer.words == nil)
    }
}

@Suite("Your own words")
struct WordsTests {
    @Test("a mark goes in as a line of its own at the caret", arguments: [
        ("", 0, "[Verse]\n", 8),
        ("abc", 0, "[Verse]\nabc", 8),
        ("abc", 3, "abc\n[Verse]\n", 12),
        ("abc\n", 4, "abc\n[Verse]\n", 12),
        ("abc\ndef", 4, "abc\n[Verse]\ndef", 12),
        ("abcdef", 3, "abc\n[Verse]\ndef", 12),
        ("abc", 99, "abc\n[Verse]\n", 12),
        ("abc", -3, "[Verse]\nabc", 8),
        ("é🎵x", 2, "é🎵\n[Verse]\nx", 11),
    ] as [(String, Int, String, Int)])
    func insert(_ text: String, _ caret: Int, _ out: String, _ outCaret: Int) {
        let r = Panel.inserting("[Verse]", into: text, at: caret)
        #expect(r.text == out && r.caret == outCaret)
    }

    @Test("a text view's UTF-16 caret and the panel's character caret convert both ways", arguments: [
        ("", 0, 0),
        ("abc", 2, 2),
        ("é🎵x", 0, 0),
        ("é🎵x", 1, 1),
        ("é🎵x", 3, 2),
        ("é🎵x", 4, 3),
        ("e\u{301}🇮🇹\r\nz", 2, 1),
        ("e\u{301}🇮🇹\r\nz", 6, 2),
        ("e\u{301}🇮🇹\r\nz", 8, 3),
        ("e\u{301}🇮🇹\r\nz", 9, 4),
    ] as [(String, Int, Int)])
    func caretRoundTrip(_ text: String, _ utf16: Int, _ characters: Int) {
        #expect(Panel.characterOffset(ofUTF16: utf16, in: text) == characters)
        #expect(Panel.utf16Offset(ofCharacter: characters, in: text) == utf16)
    }

    @Test("an offset inside a character or outside the text is held to the text", arguments: [
        ("é🎵x", 2, 1),
        ("e\u{301}🇮🇹", 1, 0),
        ("e\u{301}🇮🇹", 4, 1),
        ("abc", -1, 0),
        ("abc", 99, 3),
    ] as [(String, Int, Int)])
    func caretClamped(_ text: String, _ utf16: Int, _ characters: Int) {
        #expect(Panel.characterOffset(ofUTF16: utf16, in: text) == characters)
    }

    @Test("a character caret outside the text is held to the text")
    func characterCaretClamped() {
        #expect(Panel.utf16Offset(ofCharacter: -2, in: "é🎵x") == 0)
        #expect(Panel.utf16Offset(ofCharacter: 9, in: "é🎵x") == 4)
    }

    @Test("the sheet opens only for a sung genre, with the engine's name")
    func open() throws {
        let s = try sungSnapshot()
        let p = Panel().openingWords(s, name: "Long Way Home")
        #expect(p.mode == .words)
        guard case .words(let c) = card(s, p) else { Issue.record("not the sheet"); return }
        #expect([c.label, c.title, c.counterRight, c.nameLabel, c.name] == ["SING MY WORDS", "A tune in Jazz", "English sings best", "Name", "Long Way Home"])
        #expect(c.inserts.map(\.text) == ["+ Verse", "+ Chorus", "+ Bridge", "+ Instrumental break"])
        #expect(Panel.marks.map(\.mark) == ["[Verse]", "[Chorus]", "[Bridge]", "[Instrumental Break]"])
        #expect(c.counter == "0 sung lines · 0 of 2,000 characters")
        #expect(c.wordsError == "" && c.nameError == "" && !c.compose.enabled)
        #expect(c.note == "It is made once, with the genre's sound, and joins the end of the round when ready. The model may not sing every word as written.")
        #expect(Panel().openingWords(try Fixture.load("05-queue-full"), name: "x").mode == .player)
    }

    @Test("the buttons insert their marks at the caret; the counter counts sung lines and characters")
    func typing() throws {
        let s = try sungSnapshot()
        var p = Panel().openingWords(s, name: "Long Way Home").insertingMark(0)
        p = p.typedWords("[Verse]\nEngines hum\n", caret: 20).insertingMark(1)
        #expect(p.words?.text == "[Verse]\nEngines hum\n[Chorus]\n")
        p = p.typedWords("[Verse]\nEngines hum\n[Chorus]\nTake the long way\n(take the long way)", caret: 3)
        guard case .words(let c) = card(s, p) else { Issue.record("not the sheet"); return }
        #expect(c.counter == "3 sung lines · 66 of 2,000 characters")
        #expect(c.compose.enabled)
        p = p.typedWords(String(repeating: "la ", count: 700), caret: 0)
        guard case .words(let long) = card(s, p) else { Issue.record("not the sheet"); return }
        #expect(long.counter == "1 sung line · 2,100 of 2,000 characters")
        #expect(long.wordsError == "The words are at most 2,000 characters; these have 2,100." && !long.compose.enabled)
    }

    @Test("the rules under the fields: the words once typed in or tried, the name as typed")
    func rules() throws {
        let s = try sungSnapshot()
        let p = Panel().openingWords(s, name: "")
        guard case .words(let c) = card(s, p) else { Issue.record("not the sheet"); return }
        #expect(c.wordsError == "" && c.nameError == "A tune needs a name.")
        let (tried, words, name) = p.composingWords()
        #expect(words == nil && name == nil)
        guard case .words(let t) = card(s, tried) else { Issue.record("not the sheet"); return }
        #expect(t.wordsError == "A tune needs at least one sung line.")
        let (_, w2, _) = Panel().openingWords(s, name: "x").typedWords("[Verse]\nla", caret: 0).typedWordsName(String(repeating: "n", count: 61)).composingWords()
        #expect(w2 == nil)
    }

    @Test("compose is pending; a refusal shows and the sheet stays; accepted closes it")
    func compose() throws {
        let s = try sungSnapshot()
        let (p, words, name) = Panel().openingWords(s, name: "Long Way Home").typedWords("[Verse]\nla la", caret: 0).composingWords()
        #expect(words == "[Verse]\nla la" && name == "Long Way Home")
        guard case .words(let c) = card(s, p) else { Issue.record("not the sheet"); return }
        #expect(!c.compose.enabled && !c.cancel.enabled && c.inserts.allSatisfy { !$0.enabled })
        #expect(p.composingWords().words == nil)
        #expect(p.typedWords("other", caret: 0) == p)
        let refused = p.composedWords(.failure(Refusal(field: nil, text: "A tune with your words is already being made.")))
        guard case .words(let r) = card(s, refused) else { Issue.record("not the sheet"); return }
        #expect(r.refused == "A tune with your words is already being made." && r.compose.enabled)
        #expect(p.composedWords(.success(())).mode == .player)
        #expect(p.composedWords(.success(())).words == nil)
        let (back, close) = p.escaping(s)
        #expect(!close && back.mode == .player && back.words == nil)
    }

    @Test("the sheet closes if the genre is no longer sung")
    func follows() throws {
        let s = try sungSnapshot()
        let p = Panel().openingWords(s, name: "x")
        var plain = s
        plain.genres[4].sung = false
        #expect(p.following(plain).mode == .player)
        guard case .player = card(plain, p) else { Issue.record("not the player"); return }
    }

    @Test("the own-words tune in BEING MADE: its name, with your words, the time; with the switch off too")
    func making() throws {
        var s = try sungSnapshot()
        s.composing = false
        s.job = Job(stage: .writing, started: NOW - 9, expectS: nil, writtenS: nil, sung: true, ownWords: true, name: "Long Way Home")
        let m = try #require(try player(s).making)
        #expect(m.rows.map { [$0.name, $0.sub] } == [["Long Way Home", "with your words · being written · 0:09 so far"]])
        #expect(m.rows[0].scrapCommand == .scrapJob)
        s.job?.stage = .rendering
        s.job?.writtenS = 30
        #expect(try player(s).making?.rows[0].sub == "with your words · being rendered · 0:09 so far · written in 0:30")
        s.composing = true
        s.ready = 0
        #expect(try player(s).making?.rows.map(\.name) == ["Long Way Home", "Not started", "Not started"])
        #expect(Decide.needsTick(s, Panel(), now: NOW))
    }
}

@Suite("Grouping")
struct GroupingTests {
    @Test("a comma every three digits", arguments: [(0, "0"), (999, "999"), (1000, "1,000"), (2001, "2,001"), (1234567, "1,234,567")])
    func grouped(_ n: Int, _ text: String) {
        #expect(Format.grouped(n) == text)
    }
}
