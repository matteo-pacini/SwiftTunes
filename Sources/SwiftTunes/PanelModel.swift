import AppKit
import Observation
import TunesContract
import TunesPanel

/// The one model the popover draws: the engine's latest snapshot, the
/// panel's own state and the clock. Every click goes through here and leaves
/// as a contract command or call; the decisions are `TunesPanel`'s.
@Observable
final class PanelModel {
    private(set) var snapshot: Snapshot
    private(set) var panel = Panel()
    private(set) var now: Double
    let home: String

    /// Whether the popover is showing; the tick runs only then.
    var isOpen = false {
        didSet { updateTick() }
    }

    /// Low Power Mode is on: the backdrop holds still.
    private(set) var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    /// Called after every new snapshot, for the status item and Now Playing.
    @ObservationIgnored var onSnapshot: ((Snapshot) -> Void)?

    @ObservationIgnored private let engine: EngineAPI
    @ObservationIgnored private var observation: SnapshotObservation?
    @ObservationIgnored private var tick: Task<Void, Never>?
    @ObservationIgnored private var editorCall: Task<Void, Never>?
    @ObservationIgnored private var shareCall: Task<Void, Never>?
    @ObservationIgnored private var powerWatch: Task<Void, Never>?

    init(engine: EngineAPI, home: String) {
        self.engine = engine
        self.home = home
        snapshot = engine.snapshot
        now = Self.clock()
        observation = engine.observe { [weak self] s in
            guard let self else { return }
            snapshot = s
            panel = panel.following(s)
            now = Self.clock()
            updateTick()
            onSnapshot?(s)
        }
        powerWatch = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .NSProcessInfoPowerStateDidChange).map({ _ in () }) {
                self?.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
    }

    static func clock() -> Double { Date().timeIntervalSince1970 }

    var card: Card { Decide.card(snapshot, panel, now: now, home: home) }
    var footer: Footer? { Decide.footer(snapshot, panel, now: now) }

    // MARK: Opening and closing

    /// Each opening starts on the player and asks the engine to look again.
    func opened() {
        cancelCalls()
        panel = Panel()
        now = Self.clock()
        isOpen = true
        engine.send(.refresh)
    }

    func closed() {
        isOpen = false
        cancelCalls()
    }

    func shutdown() async {
        observation?.cancel()
        observation = nil
        tick?.cancel()
        powerWatch?.cancel()
        cancelCalls()
        await engine.shutdown()
    }

    private func cancelCalls() {
        renameCall?.cancel()
        renameCall = nil
        editorCall?.cancel()
        editorCall = nil
        shareCall?.cancel()
        shareCall = nil
    }

    private func updateTick() {
        let wanted = isOpen && Decide.needsTick(snapshot, panel, now: now)
        if wanted, tick == nil {
            tick = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard let self, !Task.isCancelled else { return }
                    now = Self.clock()
                    updateTick()
                }
            }
        } else if !wanted, let t = tick {
            t.cancel()
            tick = nil
        }
    }

    private func set(_ p: Panel) {
        panel = p
        now = Self.clock()
        updateTick()
    }

    // MARK: Commands

    func send(_ command: Command?) {
        guard let command else { return }
        engine.send(command)
    }

    func playPause() { send(Actions.playPause(snapshot)) }
    func next() { send(Actions.next(snapshot)) }
    func shuffle() { send(Actions.shuffle(snapshot)) }
    func cycleRepeat() { send(Actions.repeat(snapshot)) }
    func toggleComposer() { send(Actions.composer(snapshot)) }
    func retry() { send(Actions.retry(snapshot)) }
    func undo() { send(Actions.undo(snapshot, now: Self.clock())) }
    func seek(fraction: Double) { send(Decide.seek(snapshot, fraction: fraction)) }

    /// Asks the popover to close.
    @ObservationIgnored var close: (() -> Void)?

    /// Esc on whatever card shows.
    func escape() {
        let (p, closing) = panel.escaping(snapshot)
        if closing {
            close?()
        } else {
            editorCall?.cancel()
            shareCall?.cancel()
            set(p)
        }
    }

    // MARK: Renaming the playing tune

    @ObservationIgnored private var renameCall: Task<Void, Never>?

    func beginRename() { set(panel.beginningRename(snapshot)) }
    func typeName(_ text: String) { set(panel.typedName(text)) }

    func cancelRename() {
        renameCall?.cancel()
        renameCall = nil
        set(panel.cancellingRename())
    }

    func saveRename() {
        let (p, target, name) = panel.savingRename()
        guard let target, let name else { return }
        set(p)
        renameCall = Task { [weak self, engine] in
            let result = await engine.renameTune(target, to: name)
            guard let self, !Task.isCancelled else { return }
            set(panel.renamed(result, target: target))
        }
    }

    // MARK: Chooser

    func openChooser() { set(panel.openingChooser()) }
    func backToPlayer() { set(panel.backToPlayer()) }

    func pick(_ id: String) {
        let (p, command) = panel.picking(id, in: snapshot)
        set(p)
        send(command)
    }

    // MARK: Editor

    func addGenre() {
        editorCall?.cancel()
        set(panel.addingGenre())
    }

    func editGenre(_ id: String) {
        guard let g = snapshot.genres.first(where: { $0.id == id }) else { return }
        editorCall?.cancel()
        set(panel.editingGenre(g))
        editorCall = Task { [weak self, engine] in
            let result = await engine.genre(id: id)
            guard let self, !Task.isCancelled else { return }
            set(panel.loaded(result, id: id, now: Self.clock()))
        }
    }

    func type(_ field: EditorField, _ text: String) { set(panel.typed(field, text)) }

    func pickColour(_ index: Int, hex: String, shown: [String]) { set(panel.pickingColour(index, hex: hex, shown: shown)) }

    /// A genre's palette for its chooser tile.
    func palette(ofGenre id: String) -> Palette {
        snapshot.genres.first { $0.id == id }.map(Decide.palette(of:)) ?? Palette.made(from: id)
    }

    func save() {
        switch panel.saving(snapshot) {
        case .blocked(let p):
            set(p)
        case .send(let p, let id, let fields, let base):
            set(p)
            editorCall = Task { [weak self, engine] in
                let result = await engine.saveGenre(id: id, fields: fields, base: base)
                guard let self, !Task.isCancelled else { return }
                set(panel.saved(result, id: id, now: Self.clock()))
            }
        }
    }

    func cancelEdit() {
        editorCall?.cancel()
        editorCall = nil
        set(panel.discardingEdit())
    }

    func askDelete() { set(panel.askingDelete()) }
    func keepGenre() { set(panel.keepingGenre()) }

    func deleteGenre() {
        let (p, id) = panel.deleting()
        guard let id else { return }
        set(p)
        editorCall = Task { [weak self, engine] in
            let result = await engine.deleteGenre(id: id)
            guard let self, !Task.isCancelled else { return }
            set(panel.deleted(result, id: id))
        }
    }

    // MARK: Share sheet

    /// A share control clicked, with the tune as the card drew it.
    func openShare(_ request: ShareRequest?) {
        guard let request else { return }
        let target = request.target
        shareCall?.cancel()
        set(panel.openingShare(request))
        shareCall = Task { [weak self, engine] in
            let result = await engine.shareInfo(for: target)
            guard let self, !Task.isCancelled else { return }
            set(panel.described(result, target: target, now: Self.clock()))
        }
    }

    func closeShare() {
        shareCall?.cancel()
        shareCall = nil
        set(panel.backToPlayer())
    }

    func shareAction(_ action: ShareCard.Action) {
        switch action {
        case .share:
            // ShareLink presents the system's share sheet itself.
            return
        case .copyPath, .showInFinder:
            guard let info = panel.share?.info else { return }
            let pasteboard = NSPasteboard.general
            switch action {
            case .copyPath:
                pasteboard.clearContents()
                let done = pasteboard.setString(info.path.path, forType: .string)
                set(panel.didFileAction(.copyPath, done: done, now: Self.clock()))
            default:
                // Finder reports nothing back; the file being there is the
                // one thing that can be checked first.
                let there = FileManager.default.fileExists(atPath: info.path.path)
                if there { NSWorkspace.shared.activateFileViewerSelecting([info.path]) }
                set(panel.didFileAction(.showInFinder, done: there, now: Self.clock()))
            }
        case .export:
            let (p, target) = panel.sharing(snapshot)
            guard let target else { return }
            set(p)
            shareCall = Task { [weak self, engine] in
                let result = await engine.exportCopy(of: target)
                guard let self, !Task.isCancelled else { return }
                set(panel.exported(result, home: home, now: Self.clock()))
            }
        case .keep:
            guard let on = panel.share?.info?.pinned else { return }
            let (p, target) = panel.sharing(snapshot)
            guard let target else { return }
            set(p)
            shareCall = Task { [weak self, engine] in
                let result = await engine.setPinned(!on, for: target)
                guard let self, !Task.isCancelled else { return }
                set(panel.pinned(result, now: Self.clock()))
            }
        }
    }
}
