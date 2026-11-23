// Types with optional fields spell out encode(to:): the synthesised one omits
// a nil key, and the contract says an optional field is null, never absent.

/// The engine's whole state. Its JSON form uses the keys in
/// `docs/CONTRACT.md`.
/// Times are Unix seconds; sizes are bytes.
public struct Snapshot: Codable, Equatable, Sendable {
    /// Always 1.
    public var version: Int
    public var setup: Setup
    /// Present while downloading, and kept with its `error` after a failure;
    /// nil after a cancel or once done.
    public var download: Download?
    public var need: Need
    /// In file order.
    public var genres: [GenreSummary]
    /// The selected genre's id.
    public var genre: String?
    /// Kept tunes of the selected genre (pinned included).
    public var keptTotal: Int
    /// The composer switch.
    public var composing: Bool
    /// How many finished new tunes the composer keeps ahead.
    public var ahead: Int
    public var player: PlayerState
    /// A genre is picked and the player is not meant to play.
    public var stopped: Bool
    /// The playing (or paused) tune.
    public var tune: PlayingTune?
    /// Position in seconds, true at `posAt`.
    public var pos: Double
    /// When `pos` was sampled.
    public var posAt: Double
    /// What plays next, in order. Command indexes refer to this array.
    public var queue: [QueuedTune]
    public var shuffle: Bool
    public var `repeat`: RepeatMode
    /// Repeat is off and every kept tune was played this round.
    public var ended: Bool
    /// Kept tunes not yet played this round.
    public var roundLeft: Int
    /// The newest-N rule's N.
    public var keep: Int
    /// Finished new tunes waiting in the queue.
    public var ready: Int
    /// The playing tune is a kept one and `ready` is 0.
    public var keptPlaying: Bool
    /// Next would do something.
    public var canNext: Bool
    /// The tune being made, if any.
    public var job: Job?
    /// Median stage times of the last five tunes; nil until both stages have
    /// been timed once.
    public var expect: Expect?
    /// An offered undo.
    public var undo: Undo?
    /// The composer's model and its state.
    public var model: Model
    /// One line for the strip over the player: the first present of the
    /// genres file's error, the play error, the file error. Plain text.
    public var error: String?

    public init(
        version: Int,
        setup: Setup,
        download: Download?,
        need: Need,
        genres: [GenreSummary],
        genre: String?,
        keptTotal: Int,
        composing: Bool,
        ahead: Int,
        player: PlayerState,
        stopped: Bool,
        tune: PlayingTune?,
        pos: Double,
        posAt: Double,
        queue: [QueuedTune],
        shuffle: Bool,
        repeat: RepeatMode,
        ended: Bool,
        roundLeft: Int,
        keep: Int,
        ready: Int,
        keptPlaying: Bool,
        canNext: Bool,
        job: Job?,
        expect: Expect?,
        undo: Undo?,
        model: Model,
        error: String?
    ) {
        self.version = version
        self.setup = setup
        self.download = download
        self.need = need
        self.genres = genres
        self.genre = genre
        self.keptTotal = keptTotal
        self.composing = composing
        self.ahead = ahead
        self.player = player
        self.stopped = stopped
        self.tune = tune
        self.pos = pos
        self.posAt = posAt
        self.queue = queue
        self.shuffle = shuffle
        self.repeat = `repeat`
        self.ended = ended
        self.roundLeft = roundLeft
        self.keep = keep
        self.ready = ready
        self.keptPlaying = keptPlaying
        self.canNext = canNext
        self.job = job
        self.expect = expect
        self.undo = undo
        self.model = model
        self.error = error
    }

    enum CodingKeys: String, CodingKey {
        case version = "v"
        case setup
        case download
        case need
        case genres
        case genre
        case keptTotal = "kept_total"
        case composing
        case ahead
        case player
        case stopped
        case tune
        case pos
        case posAt = "pos_at"
        case queue
        case shuffle
        case `repeat`
        case ended
        case roundLeft = "round_left"
        case keep
        case ready
        case keptPlaying = "kept_playing"
        case canNext = "can_next"
        case job
        case expect
        case undo
        case model
        case error
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(setup, forKey: .setup)
        try c.encode(download, forKey: .download)
        try c.encode(need, forKey: .need)
        try c.encode(genres, forKey: .genres)
        try c.encode(genre, forKey: .genre)
        try c.encode(keptTotal, forKey: .keptTotal)
        try c.encode(composing, forKey: .composing)
        try c.encode(ahead, forKey: .ahead)
        try c.encode(player, forKey: .player)
        try c.encode(stopped, forKey: .stopped)
        try c.encode(tune, forKey: .tune)
        try c.encode(pos, forKey: .pos)
        try c.encode(posAt, forKey: .posAt)
        try c.encode(queue, forKey: .queue)
        try c.encode(shuffle, forKey: .shuffle)
        try c.encode(`repeat`, forKey: .repeat)
        try c.encode(ended, forKey: .ended)
        try c.encode(roundLeft, forKey: .roundLeft)
        try c.encode(keep, forKey: .keep)
        try c.encode(ready, forKey: .ready)
        try c.encode(keptPlaying, forKey: .keptPlaying)
        try c.encode(canNext, forKey: .canNext)
        try c.encode(job, forKey: .job)
        try c.encode(expect, forKey: .expect)
        try c.encode(undo, forKey: .undo)
        try c.encode(model, forKey: .model)
        try c.encode(error, forKey: .error)
    }
}

/// Whether the four model files are in place.
public enum Setup: String, Codable, Equatable, Sendable {
    case missing, downloading, ready, failed
}

public enum PlayerState: String, Codable, Equatable, Sendable {
    case none, playing, paused
}

public enum RepeatMode: String, Codable, Equatable, Sendable {
    case all, one, off
}

public struct Download: Codable, Equatable, Sendable {
    /// 1-based.
    public var file: Int
    public var files: Int
    /// One of `language model`, `diffusion model`, `text encoder`, `VAE`.
    public var name: String
    /// Over all files.
    public var done: Int64
    public var total: Int64
    /// Bytes per second.
    public var rate: Double
    public var error: String?

    public init(file: Int, files: Int, name: String, done: Int64, total: Int64, rate: Double, error: String?) {
        self.file = file
        self.files = files
        self.name = name
        self.done = done
        self.total = total
        self.rate = rate
        self.error = error
    }

    enum CodingKeys: String, CodingKey {
        case file, files, name, done, total, rate, error
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(file, forKey: .file)
        try c.encode(files, forKey: .files)
        try c.encode(name, forKey: .name)
        try c.encode(done, forKey: .done)
        try c.encode(total, forKey: .total)
        try c.encode(rate, forKey: .rate)
        try c.encode(error, forKey: .error)
    }
}

/// What setup needs.
public struct Need: Codable, Equatable, Sendable {
    /// Still to fetch.
    public var downloadBytes: Int64
    public var diskFreeBytes: Int64
    /// 8 GiB: the figure the wording quotes.
    public var ramBytes: Int64

    public init(downloadBytes: Int64, diskFreeBytes: Int64, ramBytes: Int64) {
        self.downloadBytes = downloadBytes
        self.diskFreeBytes = diskFreeBytes
        self.ramBytes = ramBytes
    }

    enum CodingKeys: String, CodingKey {
        case downloadBytes = "download_bytes"
        case diskFreeBytes = "disk_free_bytes"
        case ramBytes = "ram_bytes"
    }
}

public struct GenreSummary: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var kept: Int

    public init(id: String, name: String, kept: Int) {
        self.id = id
        self.name = name
        self.kept = kept
    }
}

/// The playing (or paused) tune.
public struct PlayingTune: Codable, Equatable, Sendable {
    /// The title once read, the file stem until then.
    public var name: String
    /// The file stem, no extension.
    public var file: String
    public var bpm: Int?
    public var key: String?
    /// nil until read.
    public var length: Double?
    public var kept: Bool
    /// Always `!kept`.
    public var new: Bool
    public var pinned: Bool
    /// 1-based place in the order made, only when kept and shuffle is off.
    public var pos: Int?
    /// 78 values in 0…1, empty until read.
    public var wave: [Double]

    public init(name: String, file: String, bpm: Int?, key: String?, length: Double?, kept: Bool, new: Bool, pinned: Bool, pos: Int?, wave: [Double]) {
        self.name = name
        self.file = file
        self.bpm = bpm
        self.key = key
        self.length = length
        self.kept = kept
        self.new = new
        self.pinned = pinned
        self.pos = pos
        self.wave = wave
    }

    enum CodingKeys: String, CodingKey {
        case name, file, bpm, key, length, kept, new, pinned, pos, wave
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(file, forKey: .file)
        try c.encode(bpm, forKey: .bpm)
        try c.encode(key, forKey: .key)
        try c.encode(length, forKey: .length)
        try c.encode(kept, forKey: .kept)
        try c.encode(new, forKey: .new)
        try c.encode(pinned, forKey: .pinned)
        try c.encode(pos, forKey: .pos)
        try c.encode(wave, forKey: .wave)
    }
}

/// A tune in the queue: as `PlayingTune` without `wave`.
public struct QueuedTune: Codable, Equatable, Sendable {
    /// The title once read, the file stem until then.
    public var name: String
    /// The file stem, no extension.
    public var file: String
    public var bpm: Int?
    public var key: String?
    /// nil until read.
    public var length: Double?
    public var kept: Bool
    /// Always `!kept`.
    public var new: Bool
    public var pinned: Bool
    /// 1-based place in the order made, only when kept and shuffle is off.
    public var pos: Int?

    public init(name: String, file: String, bpm: Int?, key: String?, length: Double?, kept: Bool, new: Bool, pinned: Bool, pos: Int?) {
        self.name = name
        self.file = file
        self.bpm = bpm
        self.key = key
        self.length = length
        self.kept = kept
        self.new = new
        self.pinned = pinned
        self.pos = pos
    }

    enum CodingKeys: String, CodingKey {
        case name, file, bpm, key, length, kept, new, pinned, pos
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(file, forKey: .file)
        try c.encode(bpm, forKey: .bpm)
        try c.encode(key, forKey: .key)
        try c.encode(length, forKey: .length)
        try c.encode(kept, forKey: .kept)
        try c.encode(new, forKey: .new)
        try c.encode(pinned, forKey: .pinned)
        try c.encode(pos, forKey: .pos)
    }
}

/// The tune being made.
public struct Job: Codable, Equatable, Sendable {
    public var stage: JobStage
    public var started: Double
    /// The median for this stage.
    public var expectS: Double?
    /// How long writing took, set while rendering.
    public var writtenS: Double?

    public init(stage: JobStage, started: Double, expectS: Double?, writtenS: Double?) {
        self.stage = stage
        self.started = started
        self.expectS = expectS
        self.writtenS = writtenS
    }

    enum CodingKeys: String, CodingKey {
        case stage
        case started
        case expectS = "expect_s"
        case writtenS = "written_s"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(stage, forKey: .stage)
        try c.encode(started, forKey: .started)
        try c.encode(expectS, forKey: .expectS)
        try c.encode(writtenS, forKey: .writtenS)
    }
}

public enum JobStage: String, Codable, Equatable, Sendable {
    case writing, rendering
}

/// Median stage times of the last five tunes.
public struct Expect: Codable, Equatable, Sendable {
    public var writingS: Double
    public var renderingS: Double

    public init(writingS: Double, renderingS: Double) {
        self.writingS = writingS
        self.renderingS = renderingS
    }

    enum CodingKeys: String, CodingKey {
        case writingS = "writing_s"
        case renderingS = "rendering_s"
    }
}

/// An offered undo.
public struct Undo: Codable, Equatable, Sendable {
    public var name: String
    public var until: Double
    /// The id of the genre whose folder the tune returns to, nil if that
    /// genre is gone.
    public var genre: String?

    public init(name: String, until: Double, genre: String?) {
        self.name = name
        self.until = until
        self.genre = genre
    }

    enum CodingKeys: String, CodingKey {
        case name, until, genre
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(until, forKey: .until)
        try c.encode(genre, forKey: .genre)
    }
}

/// The composer's model and its state.
public struct Model: Codable, Equatable, Sendable {
    /// `ACE-Step 1.5 Turbo`
    public var name: String
    /// `4B Q8`
    public var variant: String
    /// The Metal device's name from the server's log, or `Metal` before one
    /// was seen.
    public var device: String
    public var state: ModelState
    public var since: Double
    /// Seconds of silence in the plan being rewritten.
    public var silenceS: Int?
    /// The failure's text, plain.
    public var detail: String?
    public var failures: Int
    public var retryAt: Double?
    /// The server's footprint while it runs.
    public var ramUsedBytes: Int64?
    /// Always nil on the Mac.
    public var ramFreeBytes: Int64?

    public init(name: String, variant: String, device: String, state: ModelState, since: Double, silenceS: Int?, detail: String?, failures: Int, retryAt: Double?, ramUsedBytes: Int64?, ramFreeBytes: Int64?) {
        self.name = name
        self.variant = variant
        self.device = device
        self.state = state
        self.since = since
        self.silenceS = silenceS
        self.detail = detail
        self.failures = failures
        self.retryAt = retryAt
        self.ramUsedBytes = ramUsedBytes
        self.ramFreeBytes = ramFreeBytes
    }

    enum CodingKeys: String, CodingKey {
        case name
        case variant
        case device
        case state
        case since
        case silenceS = "silence_s"
        case detail
        case failures
        case retryAt = "retry_at"
        case ramUsedBytes = "ram_used_bytes"
        case ramFreeBytes = "ram_free_bytes"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(variant, forKey: .variant)
        try c.encode(device, forKey: .device)
        try c.encode(state, forKey: .state)
        try c.encode(since, forKey: .since)
        try c.encode(silenceS, forKey: .silenceS)
        try c.encode(detail, forKey: .detail)
        try c.encode(failures, forKey: .failures)
        try c.encode(retryAt, forKey: .retryAt)
        try c.encode(ramUsedBytes, forKey: .ramUsedBytes)
        try c.encode(ramFreeBytes, forKey: .ramFreeBytes)
    }
}

/// `unloaded` is the composer off; `idle` is the composer on and resting,
/// with no server process.
public enum ModelState: String, Codable, Equatable, Sendable {
    case unloaded
    case starting
    case idle
    case writing
    case rendering
    case heldMemory = "held_memory"
    case heldPower = "held_power"
    case heldHeat = "held_heat"
    case failed
    case noDevice = "no_device"
}
