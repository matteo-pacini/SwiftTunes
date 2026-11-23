import AppKit
import TunesContract
import TunesEngine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: PanelModel?
    private var statusItem: StatusItemController?
    private var nowPlaying: NowPlayingController?
    private var quitting: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let demo = DemoOptions(arguments: CommandLine.arguments)
        let engine: EngineAPI
        if let demo {
            if let name = demo.appearance { NSApp.appearance = NSAppearance(named: name) }
            engine = DemoEngine(options: demo)
        } else if let bootstrap = Self.bundleBootstrap() {
            engine = makeLiveEngine(bootstrap)
        } else {
            FileHandle.standardError.write(Data("SwiftTunes runs from SwiftTunes.app (Scripts/make-app.sh builds it), or with --demo <fixture>.\n".utf8))
            exit(1)
        }
        let model = PanelModel(engine: engine, home: NSHomeDirectory())
        let statusItem = StatusItemController(model: model)
        let nowPlaying = NowPlayingController(model: model)
        model.onSnapshot = { [weak statusItem, weak nowPlaying] s in
            statusItem?.update(s)
            nowPlaying?.update(s)
        }
        statusItem.update(model.snapshot)
        nowPlaying.update(model.snapshot)
        self.model = model
        self.statusItem = statusItem
        self.nowPlaying = nowPlaying
        if let demo { statusItem.applyDemo(demo) }
    }

    /// The engine's files inside the running bundle, or nil when the app is
    /// not running from a bundle that holds them.
    private static func bundleBootstrap() -> EngineBootstrap? {
        let contents = Bundle.main.bundleURL.appending(path: "Contents")
        let b = EngineBootstrap(
            aceServer: contents.appending(path: "Helpers/ace-server"),
            lifeline: contents.appending(path: "Helpers/tunes-lifeline"),
            defaultGenres: contents.appending(path: "Resources/genres.json"),
            pins: contents.appending(path: "Resources/pins.json")
        )
        let files = [b.aceServer, b.lifeline, b.defaultGenres, b.pins]
        guard Bundle.main.bundleURL.pathExtension == "app",
              files.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else { return nil }
        return b
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        guard quitting == nil else { return .terminateLater }
        quitting = Task {
            await model.shutdown()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
