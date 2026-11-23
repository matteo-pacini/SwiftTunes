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

    /// Called after every new snapshot, for the status item and Now Playing.
    @ObservationIgnored var onSnapshot: ((Snapshot) -> Void)?

    @ObservationIgnored private let engine: EngineAPI
    @ObservationIgnored private var observation: SnapshotObservation?
    @ObservationIgnored private var tick: Task<Void, Never>?
    @ObservationIgnored private var editorCall: Task<Void, Never>?
    @ObservationIgnored private var shareCall: Task<Void, Never>?

    init(engine: EngineAPI, home: String) {
        self.engine = engine
        self.home = home
        snapshot = engine.snapshot
        now = Self.clock()
        observation = engine.observe { [weak self] s in
            guard let self else { return }
            snapshot = s
            now = Self.clock()
            updateTick()
            onSnapshot?(s)
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
        cancelCalls()
        await engine.shutdown()
    }

    private func cancelCalls() {
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
    func scrapPlaying() { send(Actions.scrapPlaying(snapshot)) }
    func scrapQueued(_ index: Int) { send(Actions.scrapQueued(snapshot, index: index)) }
    func playQueued(_ index: Int) { send(Actions.playQueued(snapshot, index: index)) }
    func scrapJob() { send(Actions.scrapJob(snapshot)) }
    func toggleComposer() { send(Actions.composer(snapshot)) }
    func retry() { send(Actions.retry(snapshot)) }
    func undo() { send(Actions.undo(snapshot, now: Self.clock())) }
    func seek(fraction: Double) { send(Decide.seek(snapshot, fraction: fraction)) }

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

    /// The share control of the playing tune (`index` nil) or of a queue row.
    func openShare(index: Int?) {
        let (p, target) = panel.openingShare(snapshot, index: index)
        guard let target else { return }
        shareCall?.cancel()
        set(p)
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
        case .copyFile, .copyPath, .showInFinder:
            guard let info = panel.share?.info else { return }
            let pasteboard = NSPasteboard.general
            switch action {
            case .copyFile:
                pasteboard.clearContents()
                pasteboard.writeObjects([info.path as NSURL])
                set(panel.didFileAction(.copyFile, now: Self.clock()))
            case .copyPath:
                pasteboard.clearContents()
                pasteboard.setString(info.path.path, forType: .string)
                set(panel.didFileAction(.copyPath, now: Self.clock()))
            default:
                NSWorkspace.shared.activateFileViewerSelecting([info.path])
                set(panel.didFileAction(.showInFinder, now: Self.clock()))
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
