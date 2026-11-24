import AppKit
import TunesContract
import TunesPanel

/// `--demo <file.jsonl> [--demo-line N] [--demo-step S] [--demo-open CARD] [--demo-appearance light|dark] [--demo-inactive] [--demo-still-backdrop]`: the app runs on
/// a stand-in engine that shows the snapshots of a fixture file instead of
/// composing or playing, so each state can be opened and looked at. It plays
/// no sound and touches no file but the one it reads.
///
/// A time written "@-N" or "@+N" in the file is N seconds before or after
/// the launch. CARD is `player`, `chooser`, `new`, `edit:<id>`, `ask:<id>`,
/// `share` (the playing tune), `share:<queue index>`, `rename`,
/// `rename:<text typed>`, `lyrics`, `words` or `words-sample`; the
/// popover opens on it at launch.
struct DemoOptions {
    var file: URL
    var line: Int?
    var open: Open?
    /// `--demo-appearance light|dark`: the whole app in that appearance.
    var appearance: NSAppearance.Name?
    /// `--demo-step <seconds>`: from the line shown, the next line of the
    /// file every so many seconds, as if the engine had sent it.
    var step: Double?
    var stillBackdrop: Bool
    /// `--demo-still`: the clock and every animation held still.
    var still: Bool
    /// `--demo-probe <file>`: a line per 100 ms main-actor tick, with how late
    /// it came, the run loop mode, and whether the app and the popover are
    /// active, written to the file.
    var probe: URL?
    /// `--demo-no-nap`: hold a user-initiated activity, so App Nap cannot
    /// slow the process.
    var noNap: Bool
    /// `--demo-open-after <seconds>`: the card opens this long after the
    /// popover, as a click would open it.
    var openAfter: Double?
    /// `--demo-inactive`: the app gives up being active once the popover is
    /// open, to look at the cards in a window that is not key.
    var inactive: Bool

    enum Open {
        case player, chooser, new
        case edit(String), ask(String)
        case share(Int?)
        /// The rename field, with this text typed if given.
        case rename(String?)
        case lyrics
        /// The own-words sheet, empty or with sample words.
        case words(sample: Bool)

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
            case .lyrics: model.toggleLyrics()
            case .words(let sample):
                model.openWords()
                if sample {
                    model.insertMark(0)
                    model.typeWords("[Verse]\nHarbour lights on the water line\nCounting ships like I count the time\nEvery horn a name I knew\n", caret: 104)
                    model.insertMark(1)
                    model.typeWords("[Verse]\nHarbour lights on the water line\nCounting ships like I count the time\nEvery horn a name I knew\n[Chorus]\nBring the tide home\n(bring it home)\nBring the tide home tonight", caret: 186)
                }
            case .rename(let text):
                model.beginRename()
                if let text { model.typeName(text) }
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
        step = value("--demo-step").flatMap(Double.init)
        stillBackdrop = arguments.contains("--demo-still-backdrop")
        still = arguments.contains("--demo-still")
        probe = value("--demo-probe").map { URL(fileURLWithPath: $0) }
        noNap = arguments.contains("--demo-no-nap")
        openAfter = value("--demo-open-after").flatMap(Double.init)
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
        case "rename": open = .rename(nil)
        case "lyrics": open = .lyrics
        case "words": open = .words(sample: false)
        case "words-sample": open = .words(sample: true)
        case let v?:
            let parts = v.split(separator: ":", maxSplits: 1).map(String.init)
            switch (parts.first, parts.count == 2 ? parts[1] : nil) {
            case ("edit", let id?): open = .edit(id)
            case ("ask", let id?): open = .ask(id)
            case ("share", let i?): open = .share(Int(i))
            case ("rename", let text?): open = .rename(text)
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
        if let step = options.step, pick + 1 < snapshots.count {
            let later = Array(snapshots[(pick + 1)...])
            stepper = Task { [weak self] in
                for next in later {
                    try? await Task.sleep(for: .seconds(step))
                    guard let self, !Task.isCancelled else { return }
                    snapshot = next
                    changed()
                }
            }
        }
    }

    private var stepper: Task<Void, Never>?

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

    /// Enough of each command for the controls to answer a click, and the
    /// round's moves (next, previous, play again, scrap a played tune);
    /// nothing is composed or played, and a scrap offers no undo.
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
        case .next:
            guard let t = s.tune, !s.queue.isEmpty else { return }
            s.played.append(Self.queued(t))
            s.tune = Self.playing(s.queue.removeFirst(), wave: t.wave)
            s.pos = 0
            s.posAt = now
        case .previous:
            guard let t = s.tune else { return }
            if Decide.position(s, now: now) <= 3, let back = s.played.popLast() {
                s.queue.insert(Self.queued(t), at: 0)
                s.tune = Self.playing(back, wave: t.wave)
            }
            s.pos = 0
            s.posAt = now
        case .playPlayed(let index, let name):
            guard let t = s.tune, s.played.indices.contains(index), s.played[index].name == name else { return }
            s.queue = Array(s.played[(index + 1)...]) + [Self.queued(t)] + s.queue
            s.tune = Self.playing(s.played[index], wave: t.wave)
            s.played.removeSubrange(index...)
            s.pos = 0
            s.posAt = now
        case .scrapPlayed(let index, let name):
            guard s.played.indices.contains(index), s.played[index].name == name else { return }
            s.played.remove(at: index)
        case .removeModel:
            // The demo's model is a figure in a fixture; no file is touched.
            guard s.need.onDiskBytes > 0 else { return }
            s.composing = false
            s.job = nil
            s.download = nil
            s.model.state = .unloaded
            s.need.downloadBytes += s.need.onDiskBytes
            s.need.onDiskBytes = 0
            s.setup = .missing
        default:
            return
        }
        guard s != snapshot else { return }
        snapshot = s
        changed()
    }

    private static func queued(_ t: PlayingTune) -> QueuedTune {
        QueuedTune(name: t.name, file: t.file, bpm: t.bpm, key: t.key, length: t.length, kept: t.kept, new: t.new, pinned: t.pinned, pos: t.pos, sung: t.sung)
    }

    /// The demo has no files to read a wave from: the tune takes the wave
    /// that was showing.
    private static func playing(_ q: QueuedTune, wave: [Double]) -> PlayingTune {
        PlayingTune(name: q.name, file: q.file, bpm: q.bpm, key: q.key, length: q.length, kept: q.kept, new: q.new, pinned: q.pinned, pos: q.pos, wave: wave, sung: q.sung)
    }

    func genre(id: String) async -> Result<GenreFields, Refusal> {
        guard let g = snapshot.genres.first(where: { $0.id == id }) else {
            return .failure(Refusal(field: nil, text: "That genre no longer exists."))
        }
        if g.sung {
            return .success(GenreFields(name: g.name, caption: "retro synth pop, warm analog pads, gated drums, a clear lead vocal, sung verses and a big chorus",
                                        turns: ["arpeggiated bass in eighths", "a key change before the last chorus"], bpm: [90, 118], palette: g.palette, sung: true))
        }
        return .success(GenreFields(name: g.name, caption: "small combo, warm and unhurried", turns: ["late set", "a slow ballad"], bpm: [80, 120], palette: g.palette, sung: false))
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

    /// Renames the playing tune in the shown snapshot only; no file is
    /// touched.
    func renameTune(_ target: TuneTarget, to name: String) async -> Result<String, Refusal> {
        guard target.index == nil, let t = snapshot.tune, t.name == target.name || t.file == target.name else {
            return .failure(Refusal(field: nil, text: "That tune is no longer there."))
        }
        if let error = TuneRules.nameError(name) { return .failure(Refusal(field: nil, text: error)) }
        let saved = GenreRules.trim(name)
        guard saved != t.name else { return .success(saved) }
        snapshot.tune?.name = saved
        changed()
        return .success(saved)
    }

    /// Accepts the words and shows them as the job being written; nothing
    /// is composed.
    func composeWithWords(_ words: String, name: String) async -> Result<Void, Refusal> {
        guard snapshot.genres.first(where: { $0.id == snapshot.genre })?.sung == true else {
            return .failure(Refusal(field: nil, text: "That genre is not sung."))
        }
        if let error = WordsRules.wordsError(words) ?? TuneRules.nameError(name) { return .failure(Refusal(field: nil, text: error)) }
        if snapshot.job?.ownWords == true { return .failure(Refusal(field: nil, text: "A tune with your words is already being made.")) }
        snapshot.job = Job(stage: .writing, started: Date().timeIntervalSince1970, expectS: nil, writtenS: nil, sung: true, ownWords: true, name: GenreRules.trim(name))
        changed()
        return .success(())
    }

    /// The same two words every time.
    func suggestTuneName() -> String { snapshot.genre == nil ? "" : "Long Way Home" }

    func shutdown() async { stepper?.cancel() }
}
