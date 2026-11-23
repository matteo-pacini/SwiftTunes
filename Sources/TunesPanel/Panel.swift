import Foundation
import TunesContract

/// The panel's own state: which card the user has open and what each card
/// holds besides the snapshot. A value; every change returns a new one.
public struct Panel: Sendable, Equatable {
    public enum Mode: Sendable, Equatable {
        case player, chooser, editor, share
    }

    public var mode: Mode = .player
    public var editor: Editor?
    public var share: Share?
    public var notice: Notice?

    public init() {}

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
    }

    /// The share sheet on one tune.
    public struct Share: Sendable, Equatable {
        /// The tune as it was when the sheet opened.
        public var target: TuneTarget
        /// Its file stem, to find it again once its name changes to the title.
        public var file: String
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

    /// The back link, or the selected genre picked again: the player.
    public func backToPlayer() -> Panel {
        var p = self
        p.mode = .player
        p.editor = nil
        p.share = nil
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
        return .send(p, id: e.id, fields: GenreFields(name: e.values.name, caption: e.values.caption, turns: turns, bpm: bpm), base: e.base)
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
        switch mode {
        case .editor where editor?.asking == true:
            return (editor?.busy == true ? self : keepingGenre(), false)
        case .editor:
            return (discardingEdit(), false)
        case .share:
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
        p.share = Share(target: request.target, file: request.file)
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
        if s.target.index != nil, let j = snapshot.queue.firstIndex(where: { same($0.name, $0.file) }) {
            return TuneTarget(name: snapshot.queue[j].name, index: j)
        }
        if let t = snapshot.tune, same(t.name, t.file) {
            return TuneTarget(name: t.name, index: nil)
        }
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
