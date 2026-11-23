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

    init(model: PanelModel) {
        self.model = model
        super.init()
        let image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "SwiftTunes")
        image?.isTemplate = true
        if let button = item.button {
            button.image = image
            button.imagePosition = .imageLeading
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
        model.close = { [weak self] in self?.popover.performClose(nil) }
    }

    func update(_ s: Snapshot) {
        let view = Decide.statusItem(s)
        guard let button = item.button else { return }
        button.appearsDisabled = view.dim
        button.toolTip = view.help
        let title = NSMutableAttributedString()
        if !view.text.isEmpty {
            title.append(NSAttributedString(string: " " + view.text))
        }
        if let dot = view.dot {
            title.append(NSAttributedString(string: " ●", attributes: [
                .foregroundColor: NSColor(dot.color),
                .font: NSFont.systemFont(ofSize: 7),
                .baselineOffset: 4,
            ]))
        }
        button.attributedTitle = title
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
        let quit = NSMenuItem(title: "Quit SwiftTunes", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
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
            guard let self else { return }
            await open.apply(to: model)
            if demo.inactive {
                try? await Task.sleep(for: .milliseconds(300))
                NSApp.deactivate()
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
            await prepare()
            try? await Task.sleep(for: .milliseconds(800))
            if let window = popover.contentViewController?.view.window {
                print("popover window \(window.windowNumber)")
                fflush(stdout)
            }
        }
    }
}

extension Tone {
    var color: Color {
        switch self {
        case .normal: .primary
        case .soft: .secondary
        case .dim: .secondary
        case .cyan: Self.tone(light: 0x0B7A9C, dark: 0x64D2FF)
        case .green: Self.tone(light: 0x1A7F37, dark: 0x30D158)
        case .orange: Self.tone(light: 0xB85C00, dark: 0xFF9F0A)
        case .red: Self.tone(light: 0xC9001A, dark: 0xFF5A4F)
        case .accent: .accentColor
        }
    }

    /// The system's bright tones lose contrast on a light popover; these keep
    /// it in both appearances.
    private static func tone(light: UInt32, dark: UInt32) -> Color {
        func rgb(_ v: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        }
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? rgb(dark) : rgb(light)
        })
    }
}
