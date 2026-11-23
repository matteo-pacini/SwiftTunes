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
        } else {
            let contents = Bundle.main.bundleURL.appending(path: "Contents")
            engine = makeLiveEngine(EngineBootstrap(
                aceServer: contents.appending(path: "Helpers/ace-server"),
                lifeline: contents.appending(path: "Helpers/tunes-lifeline"),
                defaultGenres: contents.appending(path: "Resources/genres.json"),
                pins: contents.appending(path: "Resources/pins.json")
            ))
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
