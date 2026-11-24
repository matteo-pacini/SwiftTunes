import Foundation

/// Where the engine keeps everything.
nonisolated public struct EnginePaths: Sendable {
    /// `genres.json` and `state.json`.
    public var support: URL
    /// The four model files.
    public var models: URL
    /// The wave cache, scrapped tunes and work files.
    public var caches: URL
    /// The genres' folders and `Exports`.
    public var music: URL

    public init(support: URL, models: URL, caches: URL, music: URL) {
        self.support = support
        self.models = models
        self.caches = caches
        self.music = music
    }

    /// `~/Library/Application Support/<id>/`, `~/Library/Caches/<id>/`,
    /// `~/Music/Tunes/`.
    public static func standard(bundleID: String = "me.matteopacini.SwiftTunes") -> EnginePaths {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: bundleID, directoryHint: .isDirectory)
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: bundleID, directoryHint: .isDirectory)
        let music = fm.urls(for: .musicDirectory, in: .userDomainMask)[0].appending(path: "Tunes", directoryHint: .isDirectory)
        return EnginePaths(support: support, models: support.appending(path: "models", directoryHint: .isDirectory), caches: caches, music: music)
    }
}

/// Wall-clock time and timers. Every wait in the engine goes through it.
public protocol EngineClock: AnyObject {
    /// Unix seconds.
    var now: Double { get }
    /// Calls `fire` once, `seconds` from now, unless cancelled first.
    func after(_ seconds: Double, _ fire: @escaping @MainActor () -> Void) -> any EngineTimer
}

public protocol EngineTimer: AnyObject {
    func cancel()
}

/// What the player reports. Each carries the token of the play or next it
/// answers; the engine counts only the one it asked for last.
nonisolated public enum PlayerEvent: Sendable, Equatable {
    /// The item is playing: a play started, or the next one took over.
    case started(token: Int)
    /// The item played to its end and nothing followed.
    case ended(token: Int)
    /// Under repeat one the item reached its end and started over.
    case looped(token: Int)
    /// The item cannot be played; the reason is plain text.
    case failed(token: Int, reason: String)
}

/// The audio player: the playing item and the one after it.
public protocol TunePlayer: AnyObject {
    /// Set once by the engine.
    var onEvent: (@MainActor (PlayerEvent) -> Void)? { get set }
    /// Drops everything and plays `url` from the start, unpaused.
    func play(_ url: URL, token: Int)
    /// What plays when the current item ends; nil for nothing.
    func setNext(_ url: URL?, token: Int)
    /// Moves on to the next item now; `.started` follows for it.
    func advance()
    func setPaused(_ paused: Bool)
    func seek(to seconds: Double)
    /// Stops and drops everything; no event follows.
    func stop()
    /// Seconds into the playing item.
    var position: Double { get }
    /// The playing item starts over at its end, reported as `.looped`.
    var repeatOne: Bool { get set }
    /// The level, 0 (silent) to 1 (full), kept across items, stop and play.
    var volume: Double { get set }
}

/// Starts the model server.
public protocol ServerLauncher: AnyObject {
    /// Starts the server with `arguments` (after its own path). Lines of its
    /// stderr reach `onLine` and its exit status `onExit`, on the main actor.
    func launch(
        arguments: [String], onLine: @escaping @MainActor (String) -> Void, onExit: @escaping @MainActor (Int32) -> Void
    ) throws -> any ServerProcess
}

public protocol ServerProcess: AnyObject {
    /// Asks the server to end: SIGTERM, then SIGKILL after 5 s.
    func stop()
    /// Ends the server now: SIGKILL to its process group, then as `stop`.
    func kill()
    /// Returns once the process and everything it started have exited.
    func waitForExit() async
    /// The server's own pid, once known.
    var serverPID: Int32? { get }
}

nonisolated public enum Hold: Sendable, Equatable {
    case memory, power, heat
}

/// The system signals that hold composing.
public protocol HoldSource: AnyObject {
    /// The first hold that applies now, in the order memory, power, heat;
    /// memory pressure only when `memory`.
    func current(memory: Bool) -> Hold?
}

/// Figures read from the system.
public protocol SystemProbe: AnyObject {
    /// A process's physical footprint in bytes.
    func footprint(pid: Int32) -> Int64?
    /// Free bytes on the volume holding `url` or its nearest existing parent.
    func diskFree(near url: URL) -> Int64
}

/// Everything the engine is built from; the live one and the tests' differ
/// only here.
public struct EngineEnvironment {
    public var paths: EnginePaths
    public var aceServer: URL
    public var defaultGenres: URL
    public var pins: URL
    public var clock: any EngineClock
    public var random: any RandomNumberGenerator
    public var player: any TunePlayer
    public var launcher: any ServerLauncher
    public var holds: any HoldSource
    public var probe: any SystemProbe
    public var timeZone: TimeZone
    /// The host the server listens on and is asked at.
    public var host: String
    /// Picks the port the server is started on.
    public var freePort: () -> Int

    public init(
        paths: EnginePaths, aceServer: URL, defaultGenres: URL, pins: URL, clock: any EngineClock,
        random: any RandomNumberGenerator, player: any TunePlayer, launcher: any ServerLauncher,
        holds: any HoldSource, probe: any SystemProbe, timeZone: TimeZone = .current, host: String = "127.0.0.1",
        freePort: @escaping () -> Int = LoopbackPort.free
    ) {
        self.paths = paths
        self.aceServer = aceServer
        self.defaultGenres = defaultGenres
        self.pins = pins
        self.clock = clock
        self.random = random
        self.player = player
        self.launcher = launcher
        self.holds = holds
        self.probe = probe
        self.timeZone = timeZone
        self.host = host
        self.freePort = freePort
    }
}

nonisolated public enum LoopbackPort {
    /// A port the system just handed out on 127.0.0.1, closed again.
    public static func free() -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return 0 }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { p in
                bind(fd, p, len) == 0 && getsockname(fd, p, &len) == 0
            }
        }
        return bound ? Int(UInt16(bigEndian: addr.sin_port)) : 0
    }
}
