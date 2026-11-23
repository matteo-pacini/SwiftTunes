import Foundation
import TunesContract

/// Builds the live engine. It does not start playing or composing; the first
/// snapshot reflects the state file, the genres file and the kept tunes.
@MainActor public func makeLiveEngine(_ bootstrap: EngineBootstrap) -> EngineAPI {
    makeEngine(EngineEnvironment(
        paths: .standard(), aceServer: bootstrap.aceServer, defaultGenres: bootstrap.defaultGenres, pins: bootstrap.pins,
        clock: LiveClock(), random: SystemRandomNumberGenerator(), player: QueuePlayer(),
        launcher: LifelineLauncher(lifeline: bootstrap.lifeline, server: bootstrap.aceServer),
        holds: LiveHolds(), probe: LiveProbe()
    ))
}

/// Builds an engine from any environment: the live one, or one of fakes.
@MainActor public func makeEngine(_ environment: EngineEnvironment) -> EngineAPI {
    Engine(environment)
}

/// The live pieces, for an environment that replaces only some of them.
public enum LivePieces {
    public static func clock() -> any EngineClock { LiveClock() }
    public static func player() -> any TunePlayer { QueuePlayer() }
    public static func holds() -> any HoldSource { LiveHolds() }
    public static func probe() -> any SystemProbe { LiveProbe() }
    public static func launcher(lifeline: URL, server: URL) -> any ServerLauncher {
        LifelineLauncher(lifeline: lifeline, server: server)
    }
}
