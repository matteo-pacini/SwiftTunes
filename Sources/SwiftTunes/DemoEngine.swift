import AppKit
import TunesContract
import TunesPanel

/// `--demo <file.jsonl> [--demo-line N] [--demo-open CARD] [--demo-appearance light|dark] [--demo-inactive]`: the app runs on
/// a stand-in engine that shows the snapshots of a fixture file instead of
/// composing or playing, so each state can be opened and looked at. It plays
/// no sound and touches no file but the one it reads.
///
/// A time written "@-N" or "@+N" in the file is N seconds before or after
/// the launch. CARD is `player`, `chooser`, `new`, `edit:<id>`, `ask:<id>`,
/// `share` (the playing tune) or `share:<queue index>`; the popover opens
/// on it at launch.
struct DemoOptions {
    var file: URL
    var line: Int?
    var open: Open?
    /// `--demo-appearance light|dark`: the whole app in that appearance.
    var appearance: NSAppearance.Name?
    /// `--demo-inactive`: the app gives up being active once the popover is
    /// open, to look at the cards in a window that is not key.
    var inactive: Bool

    enum Open {
        case player, chooser, new
        case edit(String), ask(String)
        case share(Int?)

        @MainActor func apply(to model: PanelModel) async {
            switch self {
            case .player: break
            case .chooser: model.openChooser()
            case .new:
                model.openChooser()
                model.addGenre()
            case .edit(let id):
                model.openChooser()
                model.editGenre(id)
            case .ask(let id):
                model.openChooser()
                model.editGenre(id)
                // The question opens once the genre's fields have loaded.
                try? await Task.sleep(for: .milliseconds(200))
                model.askDelete()
            case .share(let index):
                guard case .player(let card) = model.card else { return }
                if let index {
                    model.openShare(card.next.rows.first { $0.index == index }?.shareRequest)
                } else {
                    model.openShare(card.now.shareRequest)
                }
            }
        }
    }

    init?(arguments: [String]) {
        func value(_ flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }
        guard let path = value("--demo") else { return nil }
        file = URL(fileURLWithPath: path)
        line = value("--demo-line").flatMap(Int.init)
        inactive = arguments.contains("--demo-inactive")
        switch value("--demo-appearance") {
        case "light": appearance = .aqua
        case "dark": appearance = .darkAqua
        default: appearance = nil
        }
        switch value("--demo-open") {
        case nil: open = nil
        case "player": open = .player
        case "chooser": open = .chooser
        case "new": open = .new
        case "share": open = .share(nil)
        case let v?:
            let parts = v.split(separator: ":", maxSplits: 1).map(String.init)
            switch (parts.first, parts.count == 2 ? parts[1] : nil) {
            case ("edit", let id?): open = .edit(id)
            case ("ask", let id?): open = .ask(id)
            case ("share", let i?): open = .share(Int(i))
            default: open = .player
            }
        }
    }
}

final class DemoEngine: EngineAPI {
    private(set) var snapshot: Snapshot
    private var handlers: [UUID: @MainActor (Snapshot) -> Void] = [:]

    init(options: DemoOptions) {
        let base = Date().timeIntervalSince1970
        let text = (try? String(contentsOf: options.file, encoding: .utf8)) ?? ""
        let times = /"@([+-]\d+(?:\.\d+)?)"/
        let snapshots: [Snapshot] = text.split(separator: "\n").compactMap { line in
            let resolved = String(line).replacing(times) { m in String(base + (Double(m.output.1) ?? 0)) }
            return try? JSONDecoder().decode(Snapshot.self, from: Data(resolved.utf8))
        }
        let pick = options.line.map { min(max(0, $0), snapshots.count - 1) } ?? snapshots.count - 1
        snapshot = snapshots.indices.contains(pick) ? snapshots[pick] : Self.empty
    }

    private static let empty = Snapshot(
        version: 1, setup: .ready, download: nil, need: Need(downloadBytes: 0, diskFreeBytes: 0, ramBytes: 8 << 30),
        genres: [], genre: nil, keptTotal: 0, composing: false, ahead: 2, player: .none, stopped: false, tune: nil,
        pos: 0, posAt: 0, queue: [], shuffle: true, repeat: .all, ended: false, roundLeft: 0, keep: 50, ready: 0,
        keptPlaying: false, canNext: false, job: nil, expect: nil, undo: nil,
        model: Model(name: "ACE-Step 1.5 Turbo", variant: "4B Q8", device: "Metal", state: .unloaded, since: 0, silenceS: nil,
                     detail: nil, failures: 0, retryAt: nil, ramUsedBytes: nil, ramFreeBytes: nil),
        error: nil
    )

    private final class Token: SnapshotObservation {
        var end: (() -> Void)?
        func cancel() {
            end?()
            end = nil
        }
        deinit { MainActor.assumeIsolated { cancel() } }
    }

    func observe(_ handler: @escaping @MainActor (Snapshot) -> Void) -> SnapshotObservation {
        let id = UUID()
        handlers[id] = handler
        handler(snapshot)
        let token = Token()
        token.end = { [weak self] in self?.handlers[id] = nil }
        return token
    }

    private func changed() {
        for h in handlers.values { h(snapshot) }
    }

    /// Enough of each command for the controls to answer a click; nothing
    /// is composed, played or moved.
    func send(_ command: Command) {
        let now = Date().timeIntervalSince1970
        var s = snapshot
        switch command {
        case .toggle, .play, .pause:
            guard s.tune != nil else { return }
            s.pos = Decide.position(s, now: now)
            s.posAt = now
            s.player = s.player == .playing ? .paused : .playing
        case .setShuffle(let on): s.shuffle = on
        case .setRepeat(let mode): s.repeat = mode
        case .setComposer(let on):
            s.composing = on
            s.model.state = on ? .idle : .unloaded
        case .selectGenre(let id):
            guard s.genres.contains(where: { $0.id == id }) else { return }
            s.genre = id
        case .seek(let to):
            s.pos = to
            s.posAt = now
        default:
            return
        }
        guard s != snapshot else { return }
        snapshot = s
        changed()
    }

    func genre(id: String) async -> Result<GenreFields, Refusal> {
        guard let g = snapshot.genres.first(where: { $0.id == id }) else {
            return .failure(Refusal(field: nil, text: "That genre no longer exists."))
        }
        return .success(GenreFields(name: g.name, caption: "small combo, warm and unhurried", turns: ["late set", "a slow ballad"], bpm: [80, 120]))
    }

    func saveGenre(id: String?, fields: GenreFields, base: GenreFields?) async -> Result<GenreSaved, Refusal> {
        .failure(Refusal(field: nil, text: "Nothing was saved: this is a demo."))
    }

    func deleteGenre(id: String) async -> Result<Void, Refusal> {
        .failure(Refusal(field: nil, text: "Nothing was deleted: this is a demo."))
    }

    func shareInfo(for target: TuneTarget) async -> Result<ShareInfo, Refusal> {
        let tune: (name: String, file: String, bpm: Int?, key: String?, length: Double?, pinned: Bool)?
        if let i = target.index, snapshot.queue.indices.contains(i) {
            let q = snapshot.queue[i]
            tune = (q.name, q.file, q.bpm, q.key, q.length, q.pinned)
        } else if let t = snapshot.tune {
            tune = (t.name, t.file, t.bpm, t.key, t.length, t.pinned)
        } else {
            tune = nil
        }
        guard let tune else { return .failure(Refusal(field: nil, text: "That tune is no longer there.")) }
        let genre = snapshot.genres.first { $0.id == snapshot.genre }?.name ?? "Tunes"
        let music = URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Music/Tunes")
        return .success(ShareInfo(
            name: tune.name, genre: genre, bpm: tune.bpm, key: tune.key, length: tune.length, bytes: 5_700_000,
            path: music.appending(path: "\(genre)/\(tune.file).m4a"),
            exportPath: music.appending(path: "Exports/\(genre) - \(tune.name).m4a"),
            pinned: tune.pinned
        ))
    }

    func setPinned(_ on: Bool, for target: TuneTarget) async -> Result<PinResult, Refusal> {
        .success(PinResult(on: on, name: target.name))
    }

    func exportCopy(of target: TuneTarget) async -> Result<URL, Refusal> {
        .failure(Refusal(field: nil, text: "Nothing was exported: this is a demo."))
    }

    func shutdown() async {}
}
