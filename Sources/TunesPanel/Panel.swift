import Foundation
import TunesContract

/// The panel's own state: which card the user has open and what each card
/// holds besides the snapshot. A value; every change returns a new one.
public struct Panel: Sendable, Equatable {
    public enum Mode: Sendable, Equatable {
        case player, chooser, editor, share, queue, words
    }

    public var mode: Mode = .player
    public var editor: Editor?
    public var share: Share?
    public var notice: Notice?
    /// The playing tune's name being edited in place.
    public var rename: Rename?
    /// The file stem of the tune whose words are open.
    public var lyricsOf: String?
    /// The own-words sheet.
    public var words: Words?

    public init() {}

    /// The own-words sheet: the words, where the caret is (in characters),
    /// the name, and how far it has got.
    public struct Words: Sendable, Equatable {
        public var text = ""
        public var caret = 0
        public var name: String
        /// The words have been typed in, or Compose was tried.
        public var touched = false
        public var refused: String?
        public var busy = false
    }

    /// The playing tune's name as a text field.
    public struct Rename: Sendable, Equatable {
        /// The tune as it was when the field opened.
        public var target: TuneTarget
        /// Its file stem: the field closes if another tune starts playing.
        public var file: String
        public var text: String
        /// The engine's refusal of the last save, until the text changes.
        public var refused: String?
        /// A save is out.
        public var busy = false
    }

    /// The footer's line for a while.
    public struct Notice: Sendable, Equatable {
        public var text: String
        public var until: Double
    }

    /// The genre editor, and the delete question asked from it.
    public struct Editor: Sendable, Equatable {
        /// nil for a new genre.
        public var id: String?
        /// The genre's name as the title gives it.
        public var name: String
        public var values: GenreFieldsText
        /// The fields typed in since it opened.
        public var touched: Set<EditorField> = []
        /// A save was tried while an error stood.
        public var tried = false
        /// The engine's refusal of the last save.
        public var refused: Refusal?
        /// Waiting for `genre(id:)`.
        public var loading: Bool
        /// What `genre(id:)` returned, sent back with the save.
        public var base: GenreFields?
        /// A save or a delete is out.
        public var busy = false
        /// The delete question is open.
        public var asking = false
        /// Why the last delete was refused.
        public var deleteError: String?
        /// The four colours as `#RRGGBB` once one is picked; nil while the
        /// genre keeps the colours made from its name.
        public var palette: [String]?
        /// The Singing switch.
        public var sung = false
    }

    /// The share sheet on one tune.
    public struct Share: Sendable, Equatable {
        /// The tune as it was when the sheet opened.
        public var target: TuneTarget
        /// Its file stem, to find it again once its name changes to the title.
        public var file: String
        /// The tune has words.
        public var sung: Bool = false
        public var info: ShareInfo?
        /// An export or a pin is out.
        public var busy = false
    }

    /// How long a notice shows, in seconds.
    public static let noticeSeconds = 6.0
}

/// The editor's boxes. The two tempo boxes share the `bpm` rule.
public enum EditorField: String, Sendable, Equatable, Hashable, CaseIterable {
    case name, caption, turns, slowest, fastest

    var group: GenreField {
        switch self {
        case .name: .name
        case .caption: .caption
        case .turns: .turns
        case .slowest, .fastest: .bpm
        }
    }
}

// MARK: - Moving between cards

extension Panel {
    /// The genre button: the chooser.
    public func openingChooser() -> Panel {
        var p = self
        p.mode = .chooser
        p.notice = nil
        return p
    }

    /// `Show all`: the queue card.
    public func openingQueue() -> Panel {
        guard mode == .player else { return self }
        var p = self
        p.mode = .queue
        p.rename = nil
        return p
    }

    /// The back link, or the selected genre picked again: the player.
    public func backToPlayer() -> Panel {
        var p = self
        p.mode = .player
        p.editor = nil
        p.share = nil
        p.words = nil
        p.notice = nil
        return p
    }

    /// A genre cell clicked: the player, and the command when it is another
    /// genre than the one selected.
    public func picking(_ id: String, in snapshot: Snapshot) -> (Panel, Command?) {
        guard snapshot.genres.contains(where: { $0.id == id }) else { return (self, nil) }
        let p = backToPlayer()
        return (p, id == snapshot.genre ? nil : .selectGenre(id: id))
    }

    /// "+ New genre": an empty editor, tempo 70 to 120.
    public func addingGenre() -> Panel {
        var p = self
        p.mode = .editor
        p.notice = nil
        p.editor = Editor(id: nil, name: "", values: GenreFieldsText(name: "", caption: "", turns: "", slowest: "70", fastest: "120"), loading: false)
        return p
    }

    /// A genre's pencil: the editor, empty until `genre(id:)` answers.
    public func editingGenre(_ genre: GenreSummary) -> Panel {
        var p = self
        p.mode = .editor
        p.notice = nil
        p.editor = Editor(id: genre.id, name: genre.name, values: GenreFieldsText(name: "", caption: "", turns: "", slowest: "", fastest: ""), loading: true)
        return p
    }

    /// The editor's Cancel or back link: the chooser, nothing saved.
    public func discardingEdit() -> Panel {
        var p = self
        p.mode = .chooser
        p.editor = nil
        return p
    }
}

// MARK: - The editor

extension Panel {
    /// The answer to `genre(id:)` for the genre `id`. An answer for another
    /// editor than the open one changes nothing.
    public func loaded(_ result: Result<GenreFields, Refusal>, id: String, now: Double) -> Panel {
        guard mode == .editor, var e = editor, e.id == id, e.loading else { return self }
        var p = self
        switch result {
        case .success(let f):
            e.values = GenreFieldsText(
                name: f.name,
                caption: f.caption,
                turns: f.turns.joined(separator: "\n"),
                slowest: f.bpm.count > 0 ? String(f.bpm[0]) : "",
                fastest: f.bpm.count > 1 ? String(f.bpm[1]) : ""
            )
            e.loading = false
            e.base = f
            e.palette = f.palette
            e.sung = f.sung
            p.editor = e
        case .failure(let r):
            p.mode = .chooser
            p.editor = nil
            p.notice = Notice(text: r.text.isEmpty ? "That genre could not be read." : r.text, until: now + Panel.noticeSeconds)
        }
        return p
    }

    /// A box's text as typed. A refusal about that box's rule, or about no
    /// box, goes with the change.
    public func typed(_ field: EditorField, _ text: String) -> Panel {
        guard mode == .editor, var e = editor, !e.loading else { return self }
        guard e.values[field] != text else { return self }
        e.values[field] = text
        e.touched.insert(field)
        if let r = e.refused, r.field == nil || r.field == field.group {
            e.refused = nil
        }
        var p = self
        p.editor = e
        return p
    }

    /// A colour picked in swatch `index` of the Colours row. The other three
    /// keep what the row showed.
    public func pickingColour(_ index: Int, hex: String, shown: [String]) -> Panel {
        guard mode == .editor, var e = editor, !e.loading, shown.indices.contains(index), RGB(hex: hex) != nil else { return self }
        var colours = e.palette ?? shown
        guard colours.count == 4, colours[index] != hex.uppercased() else { return self }
        colours[index] = hex.uppercased()
        e.palette = colours
        if let r = e.refused, r.field == nil { e.refused = nil }
        var p = self
        p.editor = e
        return p
    }

    /// The Singing switch flipped.
    public func togglingSung() -> Panel {
        guard mode == .editor, var e = editor, !e.loading, !e.busy else { return self }
        e.sung.toggle()
        if let r = e.refused, r.field == nil { e.refused = nil }
        var p = self
        p.editor = e
        return p
    }

    /// What Save does now.
    public enum SaveStep: Sendable, Equatable {
        /// Nothing to send; the panel shows every error.
        case blocked(Panel)
        /// Send these to `saveGenre`; the panel waits.
        case send(Panel, id: String?, fields: GenreFields, base: GenreFields?)
    }

    /// Save: nothing while loading, while a save is out, while a local error
    /// stands or while the engine's refusal of a box stands.
    public func saving(_ snapshot: Snapshot) -> SaveStep {
        guard mode == .editor, var e = editor, !e.loading, !e.busy else { return .blocked(self) }
        let others = Panel.otherNames(snapshot, except: e.id)
        if GenreRules.fieldError(e.values, others: others) != nil || e.refused?.field != nil {
            e.tried = true
            var p = self
            p.editor = e
            return .blocked(p)
        }
        e.busy = true
        var p = self
        p.editor = e
        let turns = e.values.turns.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == "\r\n" }).map(String.init)
        let bpm = [GenreRules.wholeNumber(e.values.slowest), GenreRules.wholeNumber(e.values.fastest)].compactMap { $0 }
        return .send(p, id: e.id, fields: GenreFields(name: e.values.name, caption: e.values.caption, turns: turns, bpm: bpm, palette: e.palette, sung: e.sung), base: e.base)
    }

    /// The answer to `saveGenre` for the editor of genre `id` (nil: new).
    public func saved(_ result: Result<GenreSaved, Refusal>, id: String?, now: Double) -> Panel {
        guard mode == .editor, var e = editor, e.id == id, e.busy else { return self }
        var p = self
        switch result {
        case .success(let s):
            p.mode = .chooser
            p.editor = nil
            if let r = s.renamed {
                p.notice = Notice(text: "Renamed \(r.from) to \(r.to). Its folder in ~/Music/Tunes moved with it.", until: now + Panel.noticeSeconds)
            }
        case .failure(let r):
            e.busy = false
            e.refused = Refusal(field: r.field, text: r.text.isEmpty ? "The genre was not saved." : r.text)
            p.editor = e
        }
        return p
    }

    /// "Delete genre…": the question.
    public func askingDelete() -> Panel {
        guard mode == .editor, var e = editor, e.id != nil, !e.busy else { return self }
        e.asking = true
        e.deleteError = nil
        var p = self
        p.editor = e
        p.notice = nil
        return p
    }

    /// "Keep it": the editor again.
    public func keepingGenre() -> Panel {
        guard mode == .editor, var e = editor, e.asking, !e.busy else { return self }
        e.asking = false
        e.deleteError = nil
        var p = self
        p.editor = e
        return p
    }

    /// "Delete <g>": the id to send to `deleteGenre`, or nil while one is out.
    public func deleting() -> (Panel, id: String?) {
        guard mode == .editor, var e = editor, e.asking, !e.busy, let id = e.id else { return (self, nil) }
        e.busy = true
        e.deleteError = nil
        var p = self
        p.editor = e
        return (p, id)
    }

    /// The answer to `deleteGenre(id:)`.
    public func deleted(_ result: Result<Void, Refusal>, id: String) -> Panel {
        guard mode == .editor, var e = editor, e.id == id, e.asking, e.busy else { return self }
        var p = self
        switch result {
        case .success:
            p.mode = .chooser
            p.editor = nil
        case .failure(let r):
            e.busy = false
            e.deleteError = r.text.isEmpty ? "The genre was not deleted." : r.text
            p.editor = e
        }
        return p
    }

    static func otherNames(_ snapshot: Snapshot, except id: String?) -> [String] {
        snapshot.genres.filter { $0.id != id }.map(\.name)
    }
}

extension GenreFieldsText {
    subscript(field: EditorField) -> String {
        get {
            switch field {
            case .name: name
            case .caption: caption
            case .turns: turns
            case .slowest: slowest
            case .fastest: fastest
            }
        }
        set {
            switch field {
            case .name: name = newValue
            case .caption: caption = newValue
            case .turns: turns = newValue
            case .slowest: slowest = newValue
            case .fastest: fastest = newValue
            }
        }
    }
}

// MARK: - Esc

extension Panel {
    /// What Esc does on the card showing: the setup cards and the player
    /// close the popover (`close` true); the chooser goes back to the player,
    /// or closes when no genre is picked; the share sheet goes back to the
    /// player; the editor discards, and its delete question keeps the genre.
    public func escaping(_ snapshot: Snapshot) -> (panel: Panel, close: Bool) {
        if snapshot.setup != .ready { return (self, true) }
        if rename != nil, mode == .player { return (cancellingRename(), false) }
        switch mode {
        case .editor where editor?.asking == true:
            return (editor?.busy == true ? self : keepingGenre(), false)
        case .editor:
            return (discardingEdit(), false)
        case .share, .queue, .words:
            return (backToPlayer(), false)
        case .chooser:
            return snapshot.genre == nil ? (self, true) : (backToPlayer(), false)
        case .player:
            return (self, true)
        }
    }
}

// MARK: - The share sheet

extension Panel {
    /// A share control clicked: the sheet on the tune as it was drawn. Ask
    /// `shareInfo(for: request.target)` about it.
    public func openingShare(_ request: ShareRequest) -> Panel {
        var p = self
        p.mode = .share
        p.notice = nil
        p.share = Share(target: request.target, file: request.file, sung: request.sung)
        return p
    }

    /// The answer to `shareInfo(for: target)`. A refusal closes the sheet
    /// with its text.
    public func described(_ result: Result<ShareInfo, Refusal>, target: TuneTarget, now: Double) -> Panel {
        guard mode == .share, var s = share, s.target == target, s.info == nil else { return self }
        switch result {
        case .success(let info):
            s.info = info
            var p = self
            p.share = s
            return p
        case .failure(let r):
            return sheetClosed(r.text, now: now)
        }
    }

    /// The tune as the engine should find it now: the queue moves while the
    /// sheet is open. Found nowhere (it has finished meanwhile), its file
    /// stem, which the engine looks up in the genre's folder.
    public func shareTargetNow(_ snapshot: Snapshot) -> TuneTarget? {
        guard let s = share else { return nil }
        let same = { (name: String, file: String) in name == s.target.name || (!s.file.isEmpty && file == s.file) }
        let playing = { snapshot.tune.flatMap { same($0.name, $0.file) ? TuneTarget(name: $0.name, index: nil) : nil } }
        let queued = { snapshot.queue.firstIndex { same($0.name, $0.file) }.map { TuneTarget(name: snapshot.queue[$0].name, index: $0) } }
        let played = { snapshot.played.firstIndex { same($0.name, $0.file) }.map { TuneTarget(name: snapshot.played[$0].name, index: $0, inPlayed: true) } }
        // The round moves on while the sheet is open: where the tune was
        // first, then wherever it is now.
        let places = s.target.inPlayed ? [played, playing, queued] : s.target.index != nil ? [queued, playing, played] : [playing, queued, played]
        for place in places { if let t = place() { return t } }
        return TuneTarget(name: s.file.isEmpty ? s.target.name : s.file, index: nil)
    }

    /// Export or Keep for good clicked: the target to send, or nil until
    /// the tune is described or while one is out.
    public func sharing(_ snapshot: Snapshot) -> (Panel, TuneTarget?) {
        guard mode == .share, var s = share, s.info != nil, !s.busy, let t = shareTargetNow(snapshot) else { return (self, nil) }
        s.busy = true
        var p = self
        p.share = s
        return (p, t)
    }

    /// The answer to `exportCopy`.
    public func exported(_ result: Result<URL, Refusal>, home: String, now: Double) -> Panel {
        guard mode == .share, let s = share, s.busy else { return self }
        switch result {
        case .success(let url):
            let dir = url.deletingLastPathComponent().path
            return sheetClosed("Exported \(s.displayName) to \(Format.tilde(dir, home: home)).", now: now)
        case .failure(let r):
            return sheetClosed(r.text, now: now)
        }
    }

    /// The answer to `setPinned`.
    public func pinned(_ result: Result<PinResult, Refusal>, now: Double) -> Panel {
        guard mode == .share, let s = share, s.busy else { return self }
        switch result {
        case .success(let r):
            return sheetClosed(r.on ? "\(s.displayName) is kept for good." : "\(s.displayName) is no longer kept for good.", now: now)
        case .failure(let r):
            return sheetClosed(r.text, now: now)
        }
    }

    /// What the app did itself with the file.
    public enum FileAction: Sendable, Equatable {
        case copyPath, showInFinder
    }

    /// One of the app's own actions on the described tune, and whether the
    /// system says it was done: the sheet closes, and the footer says what
    /// was done only when it was.
    public func didFileAction(_ action: FileAction, done: Bool, now: Double) -> Panel {
        guard mode == .share, let s = share, s.info != nil else { return self }
        guard done else {
            var p = self
            p.mode = .player
            p.share = nil
            return p
        }
        let n = s.displayName
        switch action {
        case .copyPath: return sheetClosed("Copied the path of \(n).", now: now)
        case .showInFinder: return sheetClosed("Showed \(n) in Finder.", now: now)
        }
    }

    func sheetClosed(_ text: String, now: Double) -> Panel {
        var p = self
        p.mode = .player
        p.share = nil
        p.notice = Notice(text: text, until: now + Panel.noticeSeconds)
        return p
    }
}

extension Panel.Share {
    var displayName: String { info?.name ?? target.name }
}

// MARK: - Renaming the playing tune

extension Panel {
    /// A click on the playing tune's name: the field, holding the name.
    public func beginningRename(_ snapshot: Snapshot) -> Panel {
        guard mode == .player, rename == nil, let t = snapshot.tune else { return self }
        var p = self
        p.rename = Rename(target: TuneTarget(name: t.name, index: nil), file: t.file, text: t.name)
        return p
    }

    /// The field's text as typed; the engine's last refusal goes with it.
    public func typedName(_ text: String) -> Panel {
        guard var r = rename, !r.busy, r.text != text else { return self }
        r.text = text
        r.refused = nil
        var p = self
        p.rename = r
        return p
    }

    /// The tick or Return: the target and the name to send to `renameTune`,
    /// or nil while the name breaks a rule or a save is out.
    public func savingRename() -> (Panel, TuneTarget?, String?) {
        guard var r = rename, !r.busy, TuneRules.nameError(r.text) == nil else { return (self, nil, nil) }
        r.busy = true
        r.refused = nil
        var p = self
        p.rename = r
        return (p, r.target, r.text)
    }

    /// The answer to `renameTune(target, …)`: success closes the field; a
    /// refusal shows under it and the field stays open.
    public func renamed(_ result: Result<String, Refusal>, target: TuneTarget) -> Panel {
        guard var r = rename, r.busy, r.target == target else { return self }
        var p = self
        switch result {
        case .success:
            p.rename = nil
        case .failure(let refusal):
            r.busy = false
            r.refused = refusal.text.isEmpty ? "The tune was not renamed." : refusal.text
            p.rename = r
        }
        return p
    }

    /// The cross or Esc: the old name stays.
    public func cancellingRename() -> Panel {
        var p = self
        p.rename = nil
        return p
    }

    /// A new snapshot: if another tune plays now, or none, the field closes
    /// without saving.
    public func following(_ snapshot: Snapshot) -> Panel {
        var p = self
        if let r = rename, snapshot.tune?.file != r.file { p.rename = nil }
        if let l = lyricsOf, snapshot.tune?.file != l || snapshot.tune?.sung != true { p.lyricsOf = nil }
        if p.words != nil, p.mode == .words, !Decide.sung(snapshot) { p = p.backToPlayer() }
        return p
    }
}

// MARK: - Lyrics

extension Panel {
    /// The Lyrics button: the words open or close for the playing tune.
    public func togglingLyrics(_ snapshot: Snapshot) -> Panel {
        guard mode == .player, let t = snapshot.tune, t.sung else { return self }
        var p = self
        p.lyricsOf = lyricsOf == t.file ? nil : t.file
        return p
    }
}

// MARK: - Your own words

extension Panel {
    /// The marks the sheet's buttons insert, with their buttons' words.
    public static let marks: [(button: String, mark: String)] = [
        ("+ Verse", "[Verse]"), ("+ Chorus", "[Chorus]"), ("+ Bridge", "[Bridge]"), ("+ Instrumental break", "[Instrumental Break]"),
    ]

    /// `mark` as a line of its own at `caret` (a count of characters): a
    /// line break before it unless the caret starts a line, one after it,
    /// and the caret on the line after the mark.
    public static func inserting(_ mark: String, into text: String, at caret: Int) -> (text: String, caret: Int) {
        let at = text.index(text.startIndex, offsetBy: min(max(0, caret), text.count))
        let before = text[..<at]
        let lead = before.isEmpty || before.hasSuffix("\n") ? "" : "\n"
        let insert = lead + mark + "\n"
        return (String(before) + insert + String(text[at...]), before.count + insert.count)
    }

    /// The characters of `text` that end within its first `offset` UTF-16
    /// code units (the unit a text view counts in), clamped to the text. An
    /// offset inside a character does not count that character.
    public static func characterOffset(ofUTF16 offset: Int, in text: String) -> Int {
        var units = 0
        var characters = 0
        for character in text {
            units += character.utf16.count
            if units > offset { break }
            characters += 1
        }
        return characters
    }

    /// The UTF-16 code units in the first `offset` characters of `text`,
    /// clamped to the text.
    public static func utf16Offset(ofCharacter offset: Int, in text: String) -> Int {
        text.prefix(max(0, offset)).utf16.count
    }

    /// `Sing my words…`: the sheet, for a sung genre, its name field holding
    /// `name` (the engine's offer).
    public func openingWords(_ snapshot: Snapshot, name: String) -> Panel {
        guard mode == .player, Decide.sung(snapshot), snapshot.job?.ownWords != true else { return self }
        var p = self
        p.mode = .words
        p.rename = nil
        p.notice = nil
        p.words = Words(name: name)
        return p
    }

    /// The words as typed, and the caret after the change.
    public func typedWords(_ text: String, caret: Int) -> Panel {
        guard mode == .words, var w = words, !w.busy else { return self }
        if w.text != text {
            w.text = text
            w.touched = true
            w.refused = nil
        }
        w.caret = min(max(0, caret), text.count)
        var p = self
        p.words = w
        return p
    }

    /// One of the four buttons: its mark inserted at the caret.
    public func insertingMark(_ index: Int) -> Panel {
        guard mode == .words, var w = words, !w.busy, Panel.marks.indices.contains(index) else { return self }
        let (text, caret) = Panel.inserting(Panel.marks[index].mark, into: w.text, at: w.caret)
        w.text = text
        w.caret = caret
        w.touched = true
        w.refused = nil
        var p = self
        p.words = w
        return p
    }

    /// The name as typed.
    public func typedWordsName(_ name: String) -> Panel {
        guard mode == .words, var w = words, !w.busy, w.name != name else { return self }
        w.name = name
        w.refused = nil
        var p = self
        p.words = w
        return p
    }

    /// Compose: the words and name to send to `composeWithWords`, or nil
    /// while either breaks a rule or a request is out.
    public func composingWords() -> (Panel, words: String?, name: String?) {
        guard mode == .words, var w = words, !w.busy else { return (self, nil, nil) }
        w.touched = true
        guard WordsRules.wordsError(w.text) == nil, TuneRules.nameError(w.name) == nil else {
            var p = self
            p.words = w
            return (p, nil, nil)
        }
        w.busy = true
        w.refused = nil
        var p = self
        p.words = w
        return (p, w.text, w.name)
    }

    /// The answer to `composeWithWords`: accepted closes the sheet; a
    /// refusal shows in it and it stays open.
    public func composedWords(_ result: Result<Void, Refusal>) -> Panel {
        guard mode == .words, var w = words, w.busy else { return self }
        switch result {
        case .success:
            return backToPlayer()
        case .failure(let r):
            w.busy = false
            w.refused = r.text.isEmpty ? "The tune was not asked for." : r.text
            var p = self
            p.words = w
            return p
        }
    }
}
