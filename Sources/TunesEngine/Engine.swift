import Foundation
import TunesContract
import TunesRules

/// A tune the engine holds: playing, queued, or just scrapped.
final class Tune {
    var path: URL
    var name: String
    var bpm: Int?
    var key: String?
    var length: Double?
    var kept: Bool
    var wave: [Double]
    /// The words in the file's lyrics tag, nil until read or when it has none.
    var lyrics: String?

    /// The file has words.
    var sung: Bool { !WordsRules.sungLines(lyrics ?? "").isEmpty }

    init(path: URL, name: String, bpm: Int?, key: String?, length: Double?, kept: Bool, wave: [Double]) {
        self.path = path
        self.name = name
        self.bpm = bpm
        self.key = key
        self.length = length
        self.kept = kept
        self.wave = wave
    }

    var file: String { path.lastPathComponent }
    var stem: String { TuneFiles.stem(file) }

    /// Whether a command's name names this tune.
    func named(_ name: String?) -> Bool {
        guard let name else { return true }
        return TuneFiles.names(name, tuneName: self.name, fileStem: stem)
    }
}

/// What the player was last asked to play, or to play next.
struct Ask {
    var token: Int
    var path: URL
}

final class ServerRecord {
    let port: Int
    let client: ServerClient
    var process: (any ServerProcess)?
    var lines: [String] = []
    var device: String?
    var confirmed = false
    var up = false
    var stopping = false
    var exitStatus: Int32?
    /// The id of a job asked to cancel, while the server may still be ending it.
    var cancelling: String?
    /// A job was cancelled while its POST was in flight; its id is awaited.
    var cancelPending = false

    init(port: Int, client: ServerClient) {
        self.port = port
        self.client = client
    }
}

enum JobStep {
    case lm, synth, finish
}

final class JobRecord {
    let token: Int
    let genre: Genre
    var rewrites = 0
    var id: String?
    var step: JobStep?
    let bpm: Int
    let caption: String
    let name: String
    var cut: Double?
    var plan: JSONValue = .null
    let writeAt: Double
    var renderAt: Double = 0
    var writtenS: Double?
    /// Sung: the request asks for words and the plan's words are kept.
    let sung: Bool
    /// The user's own words, sent as given; nil for the genre's own tunes.
    let words: String?
    /// Plans written again for too few sung lines; its own count.
    var thinRewrites = 0
    /// A POST for this job is waiting for its answer.
    var posting = false
    /// The job was cancelled during that POST; its id is cancelled on arrival.
    var cancelWhenPosted = false

    init(token: Int, genre: Genre, bpm: Int, caption: String, name: String, writeAt: Double, sung: Bool = false, words: String? = nil) {
        self.sung = sung
        self.words = words
        self.token = token
        self.genre = genre
        self.bpm = bpm
        self.caption = caption
        self.name = name
        self.writeAt = writeAt
    }
}

/// A tune with the user's words, waiting to be made.
struct OwnWords {
    var words: String
    var name: String
    var genreID: String
}

struct Scrap {
    var tune: Tune
    var from: URL
    var to: URL
    var pinned: Bool
    var until: Double
    /// Where it was in the round's list, for the undo to put it back.
    var place: Place = .playing

    enum Place {
        case playing
        case upcoming(Int)
        case played(Int)
    }
}

final class Observation: SnapshotObservation {
    weak var engine: Engine?
    let id: Int

    init(engine: Engine, id: Int) {
        self.engine = engine
        self.id = id
    }

    func cancel() {
        engine?.observers[id] = nil
        engine = nil
    }
}

/// An observer, held only while its token lives.
struct Observer {
    weak var token: Observation?
    let handler: @MainActor (Snapshot) -> Void
}

/// The live engine: one event loop on the main actor.
final class Engine: EngineAPI {
    let env: EngineEnvironment
    var clock: any EngineClock { env.clock }
    var player: any TunePlayer { env.player }
    var rng: any RandomNumberGenerator
    let pins: Pins?
    let pinsError: String?

    // Files
    var genresFile: URL { env.paths.support.appending(path: "genres.json") }
    var stateFile: URL { env.paths.support.appending(path: "state.json") }
    var waveDir: URL { env.paths.caches.appending(path: "wave", directoryHint: .isDirectory) }
    var workDir: URL { env.paths.caches.appending(path: "work", directoryHint: .isDirectory) }
    var scrappedDir: URL { env.paths.caches.appending(path: "scrapped", directoryHint: .isDirectory) }
    var exportsDir: URL { env.paths.music.appending(path: GenreRules.exports, directoryHint: .isDirectory) }

    // Observation
    var observers: [Int: Observer] = [:]
    var observerSeq = 0
    private(set) var snapshot: Snapshot
    var dirty = false
    var publishScheduled = false

    // Work in flight, for tests that wait until the engine is quiet.
    var inFlight = 0
    var tasks: [Int: Task<Void, Never>] = [:]
    var taskSeq = 0
    var quietWaiters: [CheckedContinuation<Void, Never>] = []
    var timers: [String: (seq: Int, timer: any EngineTimer)] = [:]
    var timerSeq = 0
    var shuttingDown = false

    // Genres and saved state
    var genres: [Genre] = []
    var genresSig: [Int64]?
    var genresError: String?
    var saved: SavedState
    var timings: (writing: [Double], rendering: [Double])
    var shuffle: Bool
    var repeatMode: RepeatMode
    var volume: Double

    // Setup and download
    var setup: Setup = .missing
    var dl: Download?
    var dlTask: Task<Void, Never>?
    var dlPrevious: Task<Void, Never>?
    var dlToken = 0
    var dlLastSent = -Double.infinity
    var dlRate = RateWindow()

    // Player and queue
    var genre: Genre?
    var current: Tune?
    var currentToken: Int?
    /// What will play after the playing tune, in order: the round's list
    /// from here on. A new tune not yet played carries its object.
    var upcoming: [QueueItem] = []
    /// The tunes played this round, oldest first; the playing one is not here.
    var played: [String] = []
    /// The next round, drawn while the last tune of this one plays with
    /// repeat on, so the player knows what follows.
    var nextRound: [String]?
    /// The tune that started last: a new round never starts with it.
    var lastStarted: String?
    var nextKeptCache: Tune?
    var anchor: String?
    var appended: Ask?
    var loading: Ask?
    var askSeq = 0
    var wantsPlay = false
    var paused = false
    /// The position as last sampled, and when. Not sampled while a tune
    /// loads: the player still reports the item being replaced.
    var pos = 0.0
    var posAt = 0.0
    /// `pos` was set by the engine just now (a start, a loop, a seek): the
    /// player's own figure may still be the old one, so it is not read.
    var posSet = false
    /// The server's footprint as last published.
    var publishedRAM: Int64?
    var playError: String?
    var fileError: String?
    /// Why the model's files could not all be removed.
    var removeError: String?
    var metaPending: Set<String> = []
    var scrap: Scrap?
    var scrappedJobs: Set<Int> = []

    // Composer
    var composing = false
    var state: ModelState = .unloaded
    var since: Double
    var detail: String?
    var silenceS: Int?
    /// The plan being written again had too few sung lines.
    var thinWords = false
    var ownWordsPending: OwnWords?
    var failures = 0
    var retryAt: Double?
    var server: ServerRecord?
    var exiting: [ObjectIdentifier: any ServerProcess] = [:]
    var job: JobRecord?
    var jobSeq = 0
    var lastDevice: String?

    init(_ env: EngineEnvironment) {
        self.env = env
        rng = env.random
        since = env.clock.now
        if let text = Files.read(env.pins) {
            do {
                pins = try Pins.parse(text)
                pinsError = nil
            } catch {
                pins = nil
                pinsError = "pins.json: \(error.description) is missing or wrong"
            }
        } else {
            pins = nil
            pinsError = "pins.json cannot be read"
        }
        saved = SavedState.parse(Files.read(env.paths.support.appending(path: "state.json")))
        timings = (saved.writing, saved.rendering)
        shuffle = saved.shuffle
        repeatMode = saved.repeat
        volume = saved.volume
        snapshot = Snapshot.empty
        prepareFolders()
        readGenres()
        checkSetup()
        player.repeatOne = repeatMode == .one
        player.volume = volume
        player.onEvent = { [weak self] event in self?.playerEvent(event) }
        snapshot = buildSnapshot()
    }

    /// Folders made, the default genres copied in, and what an earlier run
    /// left half done removed.
    private func prepareFolders() {
        let p = env.paths
        for dir in [p.support, p.caches, p.models] { try? Files.makeDirectory(dir) }
        var models = p.models
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? models.setResourceValues(values)
        if !Files.exists(genresFile), let data = FileManager.default.contents(atPath: env.defaultGenres.path) {
            try? Files.writeAtomic(data, to: genresFile)
        }
        Files.remove(genresTmp)
        Files.removeTree(scrappedDir)
        Files.removeTree(workDir)
        removeStaleParts()
    }

    /// Half-written tunes, and pins whose tune was deleted by hand (they would
    /// pin a later tune of the same name).
    private func removeStaleParts() {
        for folder in Files.list(env.paths.music) {
            let dir = env.paths.music.appending(path: folder, directoryHint: .isDirectory)
            let names = Files.list(dir)
            for n in names where n.hasPrefix(".") {
                let inner = String(n.dropFirst())
                let part = n.hasSuffix(".part") && TuneFiles.isTune(String(inner.dropLast(5)))
                let pin = String(inner.dropLast(4))
                let orphan = n.hasSuffix(".pin") && TuneFiles.isTune(pin) && !names.contains(pin)
                if part || orphan { Files.remove(dir.appending(path: n)) }
            }
        }
    }

    // MARK: - The loop's plumbing

    /// Runs `op` as tracked work on the main actor. The task is kept until
    /// it ends, and `shutdown()` cancels every one still running.
    @discardableResult
    func spawn(_ op: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        inFlight += 1
        taskSeq += 1
        let id = taskSeq
        let task = Task {
            await op()
            self.tasks[id] = nil
            self.workEnded()
        }
        // Stored before its body can run: both are on the main actor.
        tasks[id] = task
        return task
    }

    /// Runs `op` in the caller's task, counted as tracked work.
    func tracked<T>(_ op: () async -> T) async -> T {
        inFlight += 1
        defer { workEnded() }
        return await op()
    }

    private func workEnded() {
        inFlight -= 1
        if inFlight == 0 {
            let waiters = quietWaiters
            quietWaiters = []
            waiters.forEach { $0.resume() }
        }
    }

    /// Returns once no tracked work is running.
    func quiet() async {
        if inFlight == 0 { return }
        await withCheckedContinuation { quietWaiters.append($0) }
    }

    func setTimer(_ name: String, _ seconds: Double, _ fire: @escaping @MainActor () -> Void) {
        timers[name]?.timer.cancel()
        timerSeq += 1
        let seq = timerSeq
        let timer = clock.after(seconds) { [weak self] in
            guard let self, self.timers[name]?.seq == seq else { return }
            self.timers[name] = nil
            fire()
        }
        timers[name] = (seq, timer)
    }

    func cancelTimer(_ name: String) {
        timers.removeValue(forKey: name)?.timer.cancel()
    }

    func changed() {
        dirty = true
        guard !publishScheduled else { return }
        publishScheduled = true
        spawn { [weak self] in self?.publish() }
    }

    private func publish() {
        publishScheduled = false
        guard dirty else { return }
        dirty = false
        snapshot = buildSnapshot()
        let snap = snapshot
        for id in observers.keys.sorted() {
            guard let o = observers[id] else { continue }
            if o.token == nil {
                observers[id] = nil
            } else {
                o.handler(snap)
            }
        }
    }

    func observe(_ handler: @escaping @MainActor (Snapshot) -> Void) -> any SnapshotObservation {
        observerSeq += 1
        let token = Observation(engine: self, id: observerSeq)
        observers[observerSeq] = Observer(token: token, handler: handler)
        handler(snapshot)
        return token
    }

    // MARK: - Snapshot

    func genreDir(_ g: Genre) -> URL {
        env.paths.music.appending(path: g.name, directoryHint: .isDirectory)
    }

    func listTunes(_ g: Genre?) -> [String] {
        guard let g else { return [] }
        return Files.list(genreDir(g)).filter(TuneFiles.isTune)
    }

    /// The selected genre's kept tunes, in the order made.
    func keptNames() -> [String] {
        listTunes(genre).sorted()
    }

    func pinned(_ t: Tune) -> Bool {
        Files.exists(t.path.deletingLastPathComponent().appending(path: TuneFiles.pinMark(t.file)))
    }

    func serverFootprint() -> Int64? {
        server?.process?.serverPID.flatMap { env.probe.footprint(pid: $0) }
    }

    /// Sets the position the next snapshot shows.
    func setPosition(_ seconds: Double) {
        pos = seconds
        posAt = clock.now
        posSet = true
    }

    func buildSnapshot() -> Snapshot {
        readGenres()
        let now = clock.now
        let order = keptNames()
        func orderPos(_ t: Tune) -> Int? {
            guard t.kept, !shuffle, let g = genre, t.path.deletingLastPathComponent().standardizedFileURL == genreDir(g).standardizedFileURL,
                  let i = order.firstIndex(of: t.file) else { return nil }
            return i + 1
        }
        let tune = current.map {
            PlayingTune(name: $0.name, file: $0.stem, bpm: $0.bpm, key: $0.key, length: $0.length, kept: $0.kept,
                        new: !$0.kept, pinned: pinned($0), pos: orderPos($0), wave: $0.wave, sung: $0.sung, lyrics: $0.sung ? $0.lyrics : nil)
        }
        let queue = queueNow().map {
            QueuedTune(name: $0.name, file: $0.stem, bpm: $0.bpm, key: $0.key, length: $0.length, kept: $0.kept,
                       new: !$0.kept, pinned: pinned($0), pos: orderPos($0), sung: $0.sung)
        }
        var present: [String: Int64] = [:]
        for f in pins?.files ?? [] {
            let a = Files.size(env.paths.models.appending(path: f.name)) ?? 0
            let b = Files.size(env.paths.models.appending(path: f.name + ".part")) ?? 0
            present[f.name] = max(a, b)
        }
        let files = (pins?.files ?? []).map { (name: $0.name, bytes: $0.bytes) }
        let jobView: Job? = job.flatMap { j in
            switch j.step {
            case .lm?: Job(stage: .writing, started: j.writeAt, expectS: Timings.median(timings.writing), writtenS: nil,
                           sung: j.sung, ownWords: j.words != nil, name: j.words != nil ? j.name : nil)
            case .synth?, .finish?: Job(stage: .rendering, started: j.renderAt, expectS: Timings.median(timings.rendering), writtenS: j.writtenS,
                                        sung: j.sung, ownWords: j.words != nil, name: j.words != nil ? j.name : nil)
            case nil: nil
            }
        }
        let undo = scrap.map { s in
            Undo(name: s.tune.name, until: s.until,
                 genre: genres.first { genreDir($0).standardizedFileURL == s.from.deletingLastPathComponent().standardizedFileURL }?.id)
        }
        let ram = serverFootprint()
        publishedRAM = ram
        if current == nil {
            pos = 0
            posAt = now
        } else if loading == nil && !posSet {
            pos = player.position
            posAt = now
        }
        posSet = false
        return Snapshot(
            version: 1,
            setup: setup,
            download: dl,
            need: Need(downloadBytes: TuneFiles.needBytes(files, present: present),
                       diskFreeBytes: env.probe.diskFree(near: env.paths.models),
                       ramBytes: pins?.ramBytes ?? Rules.ramBytes, onDiskBytes: modelBytesOnDisk()),
            genres: genres.map { GenreSummary(id: $0.id, name: $0.name, kept: listTunes($0).count, palette: $0.palette, sung: $0.sung) },
            genre: genre?.id,
            keptTotal: order.count,
            composing: composing,
            ahead: pins?.ahead ?? 2,
            player: current == nil ? .none : (paused ? .paused : .playing),
            stopped: genre != nil && !wantsPlay,
            tune: tune,
            pos: pos,
            posAt: posAt,
            queue: queue,
            shuffle: shuffle,
            repeat: repeatMode,
            ended: ended(),
            roundLeft: roundLeft().count,
            keep: pins?.keep ?? 50,
            ready: newReady(),
            keptPlaying: current?.kept == true && newReady() == 0,
            canNext: current != nil && appended != nil,
            job: jobView,
            expect: Timings.expect(writing: timings.writing, rendering: timings.rendering),
            undo: undo,
            model: Model(name: pins?.name ?? "ACE-Step 1.5 Turbo", variant: pins?.variant ?? "4B Q8",
                         device: lastDevice ?? "Metal", state: state, since: since, silenceS: silenceS, detail: detail,
                         failures: failures, retryAt: retryAt, ramUsedBytes: ram, ramFreeBytes: nil, thinWords: thinWords),
            error: genresError ?? playError ?? fileError ?? pinsError ?? removeError,
            played: playedNow().map { QueuedTune(name: $0.name, file: $0.stem, bpm: $0.bpm, key: $0.key, length: $0.length,
                                                 kept: true, new: false, pinned: pinned($0), pos: orderPos($0), sung: $0.sung) },
            volume: volume
        )
    }

    // MARK: - Saved state and genres

    func saveState() {
        let want = SavedState(writing: timings.writing, rendering: timings.rendering, shuffle: shuffle, repeat: repeatMode, volume: volume)
        guard want != saved else { return }
        do {
            try Files.writeAtomic(Data(want.text.utf8), to: stateFile)
            saved = want
        } catch {}
    }

    var genresTmp: URL { env.paths.support.appending(path: ".genres.json.new") }

    /// Reads the genres file again when its signature changed; the last good
    /// list stays when it cannot be read.
    func readGenres() {
        let sig = Files.signature(genresFile)
        if sig == genresSig && sig != nil { return }
        genresSig = sig
        guard sig != nil else {
            genresError = "the genres file is missing"
            return
        }
        guard let text = Files.read(genresFile) else {
            genresError = "genres.json: not valid UTF-8"
            return
        }
        do {
            let parsed = try GenresFile.parse(text)
            genres = parsed.genres
            genresError = parsed.skipped.first.map { "The genre \($0) is skipped: that name is the folder for exported copies." }
        } catch {
            genresError = "genres.json: \(error.description)"
        }
    }

    func genreByID(_ id: String) -> Genre? { genres.first { $0.id == id } }

    func checkSetup() {
        if dlTask != nil {
            setup = .downloading
        } else if let files = pins?.files, files.allSatisfy({ Files.size(env.paths.models.appending(path: $0.name)) == $0.bytes }) {
            setup = .ready
        } else if dl?.error != nil {
            setup = .failed
        } else {
            setup = .missing
        }
    }

    // MARK: - Commands

    func send(_ command: Command) {
        guard !shuttingDown else { return }
        switch command {
        case .selectGenre(let id): selectGenre(id)
        case .toggle: toggle()
        case .play: if current == nil && loading == nil || paused || ended() { toggle() }
        case .pause: if (current != nil || loading != nil) && !paused { toggle() }
        case .stop: stop()
        case .next: if current != nil && appended != nil { player.advance() }
        case .seek(let t): seek(t)
        case .setComposer(let on): setComposer(on)
        case .setShuffle(let on): setModes(shuffle: on, repeat: repeatMode)
        case .setRepeat(let mode): setModes(shuffle: shuffle, repeat: mode)
        case .setVolume(let level, let dragging): setVolume(level, dragging: dragging)
        case .scrapPlaying(let name): scrapPlaying(name)
        case .scrapQueued(let i, let name): scrapQueued(i, name)
        case .scrapJob: scrapJob()
        case .undo: undo()
        case .playQueued(let i, let name): playQueued(i, name)
        case .retry: retry()
        case .download: download()
        case .cancelDownload: cancelDownload()
        case .removeModel:
            removeModel()
        case .previous: previous()
        case .playPlayed(let i, let name): playPlayed(i, name)
        case .scrapPlayed(let i, let name): scrapPlayed(i, name)
        case .refresh:
            genresSig = nil
            readGenres()
            changed()
        }
    }

    func selectGenre(_ id: String) {
        readGenres()
        guard let g = genreByID(id), genre?.id != id else { return }
        wantsPlay = true
        dropOwnWords()
        composerOff()
        genre = g
        upcoming = []
        newRound()
        if let cand = nextCandidate() {
            // Shown as playing at once: no snapshot may put the old genre's
            // tune or pause under the new genre.
            upcoming.removeFirst()
            current = cand
            paused = false
            setPosition(0)
            playNow(cand)
        } else {
            haltPlayer()
        }
        changed()
    }

    func toggle() {
        if current != nil || loading != nil {
            paused.toggle()
            player.setPaused(paused)
            changed()
        } else if genre != nil {
            if ended() { newRound(avoid: lastStarted) }
            wantsPlay = true
            startIfIdle()
            changed()
        }
    }

    func stop() {
        guard genre != nil, wantsPlay || current != nil || loading != nil else { return }
        if let c = current { played.append(c.file) }
        wantsPlay = false
        current = nil
        currentToken = nil
        appended = nil
        loading = nil
        player.stop()
        changed()
    }

    func seek(_ t: Double) {
        guard let cur = current, t.isFinite else { return }
        let clamped = min(max(0, t), cur.length ?? .infinity)
        player.seek(to: clamped)
        // The player's seek completes later; show where it is going.
        setPosition(clamped)
        changed()
    }

    /// Nothing plays from now on; not a stop by the user.
    func haltPlayer() {
        if current != nil || appended != nil || loading != nil {
            current = nil
            currentToken = nil
            appended = nil
            loading = nil
            player.stop()
            changed()
        }
    }

    func setModes(shuffle newShuffle: Bool, repeat newRepeat: RepeatMode) {
        guard newShuffle != shuffle || newRepeat != repeatMode else { return }
        let wasEnded = ended()
        if newShuffle != shuffle { redrawQueue(shuffle: newShuffle) }
        if newRepeat == .off { nextRound = nil }
        shuffle = newShuffle
        repeatMode = newRepeat
        player.repeatOne = newRepeat == .one
        saveState()
        changed()
        if wasEnded && newRepeat != .off {
            newRound(avoid: lastStarted)
            startIfIdle()
        } else {
            syncPlaylist()
        }
    }

    /// Applied at once. This command saves the level only for `dragging:
    /// false`; any other save, and shutdown, also write the level of that moment.
    func setVolume(_ level: Double, dragging: Bool) {
        guard level.isFinite else { return }
        let clamped = min(max(0, level), 1)
        if clamped != volume {
            volume = clamped
            player.volume = clamped
            changed()
        }
        if !dragging { saveState() }
    }

    // MARK: - The player

    func newToken() -> Int {
        askSeq += 1
        return askSeq
    }

    func playNow(_ tune: Tune) {
        appended = nil
        // The item it replaces is no longer the one asked for.
        currentToken = nil
        let token = newToken()
        loading = Ask(token: token, path: tune.path)
        paused = false
        player.play(tune.path, token: token)
    }

    func startIfIdle() {
        guard current == nil, wantsPlay, loading == nil, let cand = nextCandidate() else { return }
        playNow(cand)
    }

    /// Keeps the player's next item the next candidate.
    func syncPlaylist() {
        guard current != nil else {
            startIfIdle()
            return
        }
        let cand = nextCandidate()
        if cand?.path != appended?.path {
            let token = newToken()
            player.setNext(cand?.path, token: token)
            appended = cand.map { Ask(token: token, path: $0.path) }
        }
    }

    func playerEvent(_ event: PlayerEvent) {
        switch event {
        case .started(let token):
            // Only the item asked for last counts: a report may name an item
            // since replaced, as an earlier genre's tune after a pick.
            guard let ask = loading ?? appended, ask.token == token else { return }
            onTrack(ask, token: token)
        case .looped(let token):
            guard token == currentToken, loading == nil else { return }
            setPosition(0)
            changed()
        case .ended(let token):
            guard token == currentToken, loading == nil, current != nil else { return }
            onIdle(natural: true)
        case .failed(let token, let reason):
            guard token == loading?.token || token == currentToken || token == appended?.token else { return }
            playError = "The tune could not be played: \(reason)"
            loading = nil
            if token == appended?.token && token != currentToken {
                appended = nil
            } else if current != nil {
                onIdle(natural: false)
            }
            changed()
        }
    }

    func onTrack(_ ask: Ask, token: Int) {
        let path = ask.path
        let name = path.lastPathComponent
        advance(to: path)
        currentToken = token
        if current?.kept == true { anchor = name }
        lastStarted = name
        loading = nil
        appended = nil
        playError = nil
        setPosition(0)
        syncPlaylist()
        changed()
        maybeCompose()
    }

    func onIdle(natural: Bool) {
        // It played: it stays in the round's list.
        if let c = current { played.append(c.file) }
        current = nil
        currentToken = nil
        appended = nil
        loading = nil
        if !natural { wantsPlay = false }
        changed()
        startIfIdle()
    }

    // MARK: - Kept tunes and the wave cache

    func waveFile(_ path: URL) -> URL {
        let folder = path.deletingLastPathComponent().lastPathComponent
        let gid = genres.first { $0.name == folder }?.id ?? folder
        return waveDir.appending(path: gid, directoryHint: .isDirectory).appending(path: path.lastPathComponent + ".json")
    }

    func readWave(_ path: URL) -> TuneMeta? {
        guard let sig = Files.signature(path), let text = Files.read(waveFile(path)),
              let c = try? JSONValue.parse(text), c["size"] == .int(Int(sig[1])), c["mtime"] == .int(Int(sig[0]))
        else { return nil }
        var name: String?
        if case .string(let s)? = c["name"] { name = s }
        guard let length = c["length"]?.number, case .array(let w)? = c["wave"] else { return nil }
        var lyrics: String?
        if case .string(let l)? = c["lyrics"] { lyrics = l }
        return TuneMeta(name: name, length: length, wave: w.compactMap(\.number), lyrics: lyrics)
    }

    func writeWave(_ path: URL, _ meta: TuneMeta) {
        guard let sig = Files.signature(path) else { return }
        var fields: [(key: String, value: JSONValue)] = []
        if let n = meta.name { fields.append(("name", .string(n))) }
        fields += [("length", .double(meta.length)), ("wave", .array(meta.wave.map { .double($0) }))]
        if let l = meta.lyrics { fields.append(("lyrics", .string(l))) }
        fields += [("size", .int(Int(sig[1]))), ("mtime", .int(Int(sig[0])))]
        try? Files.writeAtomic(Data(JSONValue.object(fields).dumps().utf8), to: waveFile(path))
    }

    /// A kept tune: its name, length and wave from the wave cache, else read
    /// from the file in the background when `decode`.
    func keptTune(_ path: URL, decode: Bool = true) -> Tune {
        let parsed = TuneFiles.parse(path.lastPathComponent)
        let t = Tune(path: path, name: TuneFiles.stem(path.lastPathComponent), bpm: parsed?.bpm, key: parsed?.key,
                     length: nil, kept: true, wave: [])
        if let cached = readWave(path) {
            if let n = cached.name { t.name = n }
            t.length = cached.length
            t.wave = cached.wave
            t.lyrics = cached.lyrics
        } else if decode && !metaPending.contains(path.path) {
            metaPending.insert(path.path)
            spawn { [weak self] in
                let meta = try? await AudioWork.meta(of: path)
                self?.keptMetaDone(path, meta)
            }
        }
        return t
    }

    func keptMetaDone(_ path: URL, _ meta: TuneMeta?) {
        // Not pending any more (a rename came between): this read is stale.
        guard metaPending.remove(path.path) != nil, let meta else { return }
        writeWave(path, meta)
        for t in [current, nextKept].compactMap({ $0 }) where t.path == path {
            if let n = meta.name { t.name = n }
            t.length = meta.length
            t.wave = meta.wave
            t.lyrics = meta.lyrics
            changed()
        }
    }
}

extension Snapshot {
    /// A placeholder until the first real snapshot is built.
    static let empty = Snapshot(
        version: 1, setup: .missing, download: nil, need: Need(downloadBytes: 0, diskFreeBytes: 0, ramBytes: Rules.ramBytes),
        genres: [], genre: nil, keptTotal: 0, composing: false, ahead: 2, player: .none, stopped: false, tune: nil, pos: 0,
        posAt: 0, queue: [], shuffle: true, repeat: .all, ended: false, roundLeft: 0, keep: 50, ready: 0, keptPlaying: false,
        canNext: false, job: nil, expect: nil, undo: nil,
        model: Model(name: "ACE-Step 1.5 Turbo", variant: "4B Q8", device: "Metal", state: .unloaded, since: 0, silenceS: nil,
                     detail: nil, failures: 0, retryAt: nil, ramUsedBytes: nil, ramFreeBytes: nil),
        error: nil
    )
}
