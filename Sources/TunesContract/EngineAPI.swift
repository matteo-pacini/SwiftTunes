import Foundation

/// The engine as the app sees it. The app never reads the engine's files,
/// never talks to `ace-server`, and never plays audio itself.
@MainActor
public protocol EngineAPI: AnyObject {
    /// The latest state. Always complete; never partially updated.
    var snapshot: Snapshot { get }

    /// Calls `handler` once now with the current snapshot, then after every
    /// change, at most once per main run loop pass. Returns a token; the
    /// observation ends when the token is cancelled or released.
    func observe(_ handler: @escaping @MainActor (Snapshot) -> Void) -> SnapshotObservation

    /// Fire and forget. A command that does not apply is ignored silently and
    /// produces no snapshot. Never throws, never blocks.
    func send(_ command: Command)

    /// The stored fields of a genre, to be passed back unchanged as `base`.
    func genre(id: String) async -> Result<GenreFields, Refusal>
    /// Saves a new genre (`id` and `base` nil) or an edited one. The fields
    /// may be untrimmed; the engine's refusal is final.
    func saveGenre(id: String?, fields: GenreFields, base: GenreFields?) async -> Result<GenreSaved, Refusal>
    func deleteGenre(id: String) async -> Result<Void, Refusal>
    func shareInfo(for target: TuneTarget) async -> Result<ShareInfo, Refusal>
    func setPinned(_ on: Bool, for target: TuneTarget) async -> Result<PinResult, Refusal>
    /// Returns the URL written.
    func exportCopy(of target: TuneTarget) async -> Result<URL, Refusal>
    /// Gives a tune a new name (its title tag; the file keeps its name) and
    /// returns the name as saved. A name equal to the current one succeeds
    /// and writes nothing. Refusals have no field.
    func renameTune(_ target: TuneTarget, to name: String) async -> Result<String, Refusal>

    /// Stops the player, cancels the job, stops the server and waits until no
    /// child process remains. Called once, from applicationWillTerminate.
    func shutdown() async
}

/// A token returned by `EngineAPI.observe`.
public protocol SnapshotObservation: AnyObject { func cancel() }

/// The bundle paths the live engine is built from.
public struct EngineBootstrap: Sendable {
    /// `Contents/Helpers/ace-server`
    public var aceServer: URL
    /// `Contents/Helpers/tunes-lifeline`
    public var lifeline: URL
    /// `Contents/Resources/genres.json`
    public var defaultGenres: URL
    /// `Contents/Resources/pins.json`
    public var pins: URL

    public init(aceServer: URL, lifeline: URL, defaultGenres: URL, pins: URL) {
        self.aceServer = aceServer
        self.lifeline = lifeline
        self.defaultGenres = defaultGenres
        self.pins = pins
    }
}
