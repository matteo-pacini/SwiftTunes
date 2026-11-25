import AppKit
import ServiceManagement
import SwiftUI
import TunesContract
import TunesPanel

/// The menu bar item: a left click toggles the popover, a right click opens
/// the menu (the version, Start at Login, Quit).
final class StatusItemController: NSObject, NSPopoverDelegate, NSMenuDelegate {
    private let model: PanelModel
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let menu = NSMenu()
    /// Why the last Start at Login change failed, as the system said it.
    private var loginError: String?
    private var launchOpen: Task<Void, Never>?
    private let look = StatusLook()
    private lazy var content = PassThroughHostingView(rootView: StatusContent(look: look))

    init(model: PanelModel) {
        self.model = model
        super.init()
        if let button = item.button {
            button.addSubview(content)
            button.setAccessibilityLabel("SwiftTunes")
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        let host = NSHostingController(rootView: PopoverView(model: model))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        menu.delegate = self
        // Items say for themselves whether they act: Remove Music Model…, shown
        // while the pins list no models, is off with nothing on disk.
        menu.autoenablesItems = false
        model.close = { [weak self] in self?.popover.performClose(nil) }
        model.confirm = { Self.confirm($0) }
    }

    func update(_ s: Snapshot) {
        let view = Decide.statusItem(s)
        look.item = view
        look.playing = s.player == .playing
        item.button?.toolTip = view.help
        let size = content.fittingSize
        item.length = size.width
        if let button = item.button {
            content.frame = NSRect(x: 0, y: (button.bounds.height - size.height) / 2, width: size.width, height: size.height)
        }
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            popover.performClose(nil)
            item.menu = menu
            item.button?.performClick(nil)
            item.menu = nil
        } else {
            toggle()
        }
    }

    private func toggle() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            show()
        }
    }

    private func show() {
        guard let button = item.button else { return }
        model.opened()
        // A popover takes its look from the status bar it hangs from unless
        // told otherwise; nil keeps that, a demo's forced look overrides it.
        popover.appearance = NSApp.appearance
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidClose(_ notification: Notification) {
        model.closed()
    }

    // MARK: The menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let title = NSMenuItem(title: version.map { "SwiftTunes \($0)" } ?? "SwiftTunes", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        let login = NSMenuItem(title: "Start at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        if let loginError {
            let line = NSMenuItem(title: loginError, action: nil, keyEquivalent: "")
            line.isEnabled = false
            menu.addItem(line)
        }
        menu.addItem(.separator())
        let models = Decide.modelsMenu(model.snapshot)
        let item = NSMenuItem(title: models.title, action: #selector(modelsItem), keyEquivalent: "")
        item.target = self
        item.isEnabled = models.enabled
        menu.addItem(item)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit SwiftTunes", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    /// `Music Models…` opens the popover on the models card; with no models
    /// listed, `Remove Music Model…` asks first.
    @objc private func modelsItem() {
        let models = Decide.modelsMenu(model.snapshot)
        guard models.enabled else { return }
        if models.opensCard {
            show()
            model.openModels()
        } else if Self.confirm(models.removal) {
            model.send(models.removal.command)
        }
    }

    /// Asks first; Cancel is the default, Remove the destructive choice.
    private static func confirm(_ removal: ModelRemoval) -> Bool {
        let alert = NSAlert()
        alert.messageText = removal.alertTitle
        alert.informativeText = removal.alertText
        alert.addButton(withTitle: removal.cancel)
        let remove = alert.addButton(withTitle: removal.remove)
        remove.hasDestructiveAction = true
        NSApp.activate()
        return alert.runModal() == .alertSecondButtonReturn
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
    }

    // MARK: Demo

    /// Opens the popover on the card the demo names, for looking at it.
    func applyDemo(_ demo: DemoOptions) {
        guard let open = demo.open else { return }
        openOnLaunch { [weak self] in
            if let after = demo.openAfter { try? await Task.sleep(for: .seconds(after)) }
            guard let self else { return }
            await open.apply(to: model)
            if demo.inactive {
                try? await Task.sleep(for: .milliseconds(300))
                NSApp.deactivate()
            }
        }
    }

    private var probeTask: Task<Void, Never>?
    private var activity: NSObjectProtocol?

    /// The demo's probe: how late each 100 ms main-actor tick comes.
    func startProbe(_ demo: DemoOptions) {
        if demo.noNap {
            activity = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "demo probe")
        }
        guard let url = demo.probe else { return }
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let file = try? FileHandle(forWritingTo: url)
        // The run loop's own view, independent of the main actor: a timer in
        // the common modes logs the mode it fires in.
        let begun = Date()
        let host = popover.contentViewController
        let timer = Timer(timeInterval: 0.25, repeats: true) { _ in
            MainActor.assumeIsolated {
                let size = host?.preferredContentSize ?? .zero
                let frame = host?.view.window?.frame.size ?? .zero
                let line = String(format: "%.2f timer mode %@ preferred %.1f x %.1f window %.1f x %.1f\n", Date().timeIntervalSince(begun),
                                  RunLoop.main.currentMode?.rawValue ?? "-", size.width, size.height, frame.width, frame.height)
                file?.write(Data(line.utf8))
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        probeTask = Task { [weak self] in
            let start = Date()
            var expected = start
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                expected += 0.1
                let now = Date()
                guard let self else { return }
                let card = String(describing: model.card).prefix(while: { $0 != "(" })
                let line = String(format: "%.2f late %4.0f ms mode %@ active %d key %d card %@\n",
                                  now.timeIntervalSince(start), now.timeIntervalSince(expected) * 1000,
                                  RunLoop.main.currentMode?.rawValue ?? "-", NSApp.isActive ? 1 : 0,
                                  popover.contentViewController?.view.window?.isKeyWindow == true ? 1 : 0, String(card))
                file?.write(Data(line.utf8))
                expected = now
            }
        }
    }

    /// `--open-on-launch`: opens the popover shortly after launch and prints
    /// its window number on stdout, so a screenshot can be taken of it.
    func openOnLaunch(then prepare: @escaping @MainActor () async -> Void = {}) {
        launchOpen = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self else { return }
            show()
            // Printed before the card is prepared, with no wait after: with
            // the editor showing, a main-actor sleep here was seen not to
            // return; the caller waits before its screenshot instead.
            if let window = popover.contentViewController?.view.window {
                print("popover window \(window.windowNumber)")
                fflush(stdout)
            }
            await prepare()
        }
    }
}

/// What the status item draws.
@Observable
final class StatusLook {
    /// nil before the first snapshot.
    var item: StatusItem?
    var playing = false
}

/// The waveform symbol (moving while a tune plays, still otherwise), the
/// genre's name while playing, the composer's dot.
struct StatusContent: View {
    let look: StatusLook

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "waveform")
                .symbolEffect(.variableColor.iterative, options: .repeat(.continuous), isActive: look.playing)
            if let text = look.item?.text, !text.isEmpty {
                Text(verbatim: text)
            }
        }
        .font(.system(size: 13))
        .opacity(look.item?.dim ?? true ? 0.45 : 1)
        .overlay(alignment: .topTrailing) {
            if let dot = look.item?.dot {
                Circle().fill(dot.color).frame(width: 5, height: 5).offset(x: 5, y: 1)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .fixedSize()
    }
}

/// Draws SwiftUI inside the status bar button and leaves every click to
/// the button.
final class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
