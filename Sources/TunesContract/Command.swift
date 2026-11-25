/// What the app asks of the engine through `EngineAPI.send`. Every command
/// aimed at a tune carries its name; the engine acts only if the tune at that
/// place has that name or that file stem.
public enum Command: Sendable, Equatable {
    /// Unknown or already selected: ignored.
    case selectGenre(id: String)
    case toggle
    /// As toggle when paused, stopped or ended; nothing when playing.
    case play
    /// Nothing unless playing.
    case pause
    /// Halts; `stopped` becomes true.
    case stop
    /// Only when `canNext`.
    case next
    /// Seconds, clamped to 0…length.
    case seek(to: Double)
    case setComposer(on: Bool)
    case setShuffle(on: Bool)
    case setRepeat(RepeatMode)
    /// The player's level, clamped to 0…1; a level that is not finite is
    /// ignored. `dragging` is true while the pointer holds the slider (spec,
    /// "Volume").
    case setVolume(to: Double, dragging: Bool)
    case scrapPlaying(name: String)
    case scrapQueued(index: Int, name: String)
    /// Cancels the tune being made; no undo.
    case scrapJob
    case undo
    case playQueued(index: Int, name: String)
    /// Only in `failed` or `no_device`.
    case retry
    /// Fetches what the chosen model lacks.
    case download
    /// Makes the model with this id the chosen one. Ignored unless the pins
    /// list it; once any model is on disk, ignored unless that one is.
    case chooseModel(id: String)
    /// Fetches that model's own file and any shared file missing, carrying
    /// on from a part file. Ignored when it is on disk or a download runs.
    case downloadModel(id: String)
    /// Removes that model's own file and its part file only. Ignored for the
    /// chosen model while another model is on disk. With no other model on
    /// disk it acts as `removeModel`.
    case removeOneModel(id: String)
    case cancelDownload
    /// Re-reads the genres file and memory, then notifies.
    case refresh
    /// Removes the music model's files; ignored when nothing is on disk.
    case removeModel
    /// Restarts the playing tune, or within its first 3 s goes back one.
    /// Nothing when no tune plays.
    case previous
    /// Plays `played[index]` again; ignored unless that tune is there.
    case playPlayed(index: Int, name: String)
    /// Scraps `played[index]`: it leaves the round, with the usual undo.
    case scrapPlayed(index: Int, name: String)
}

/// A tune for the async calls: the playing tune when `index` is nil, else
/// `queue[index]`. With no index and no match, the engine looks `name` up as
/// a file in the selected genre's folder.
public struct TuneTarget: Sendable, Equatable {
    /// The tune's name or its file stem.
    public var name: String
    /// nil: the playing tune, else a queue index.
    public var index: Int?
    /// `index` is an index into `played`, not `queue`.
    public var inPlayed: Bool

    public init(name: String, index: Int?, inPlayed: Bool = false) {
        self.name = name
        self.index = index
        self.inPlayed = inPlayed
    }
}
