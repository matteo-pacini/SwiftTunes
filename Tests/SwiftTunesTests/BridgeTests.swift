import AppKit
import SwiftUI
import Testing
import TunesContract
import TunesPanel
@testable import SwiftTunes

/// The first view of type `T` under `view`, depth first.
private func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
    if let match = view as? T { return match }
    for sub in view.subviews { if let match = find(type, in: sub) { return match } }
    return nil
}

/// The words as the panel holds them: what the editor reports is stored,
/// and the editor is drawn again from what is stored, as the popover does.
@MainActor
private final class Words {
    var text: String
    var caret: Int
    var reports: [(String, Int)] = []
    let host: NSHostingView<PlainTextEditor>

    init(_ text: String, caret: Int) {
        self.text = text
        self.caret = caret
        host = NSHostingView(rootView: PlainTextEditor(text: text, caret: caret, label: "Words", changed: { _, _ in }))
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 190)
        redraw()
    }

    /// The editor again, with the values stored now.
    func redraw() {
        host.rootView = PlainTextEditor(text: text, caret: caret, label: "Words") { [weak self] text, caret in
            self?.reports.append((text, caret))
            self?.text = text
            self?.caret = caret
        }
        host.layoutSubtreeIfNeeded()
    }

    var view: NSTextView {
        get throws { try #require(find(NSTextView.self, in: host)) }
    }
}

@Suite("PlainTextEditor")
@MainActor
struct PlainTextEditorTests {
    @Test("the text and the caret given are what the view shows, in UTF-16")
    func shows() throws {
        let words = Words("é🎵\nabc", caret: 3)
        let view = try words.view
        #expect(view.string == "é🎵\nabc")
        #expect(view.selectedRange() == NSRange(location: 4, length: 0))
        #expect(!view.isRichText && view.allowsUndo)
        #expect(!view.isAutomaticQuoteSubstitutionEnabled && !view.isAutomaticDashSubstitutionEnabled && !view.isAutomaticTextReplacementEnabled)
        #expect(words.reports.isEmpty)
    }

    @Test("typing reports the whole text and the caret in characters, and drawing them again moves nothing")
    func typing() throws {
        let words = Words("🎵ab", caret: 1)
        let view = try words.view
        view.insertText("x", replacementRange: view.selectedRange())
        #expect(words.text == "🎵xab" && words.caret == 2)
        let reported = words.reports.count
        words.redraw()
        #expect(view.string == "🎵xab")
        #expect(view.selectedRange() == NSRange(location: 3, length: 0))
        #expect(words.reports.count == reported)
    }

    @Test("a caret moved in the view is reported, at the selection's end")
    func selection() throws {
        let words = Words("ab\ncd", caret: 0)
        let view = try words.view
        view.setSelectedRange(NSRange(location: 1, length: 3))
        #expect(words.caret == 4 && words.text == "ab\ncd")
    }

    @Test("a mark inserted by the panel goes in as its own line, the caret after it",
          arguments: [("abcdef", 3, "abc\n[Chorus]\ndef", 13), ("abc\n", 4, "abc\n[Chorus]\n", 13), ("", 0, "[Chorus]\n", 9)])
    func insert(_ text: String, _ caret: Int, _ out: String, _ outCaret: Int) throws {
        let words = Words(text, caret: 0)
        let view = try words.view
        view.setSelectedRange(NSRange(location: Panel.utf16Offset(ofCharacter: caret, in: text), length: 0))
        #expect(words.caret == caret)
        (words.text, words.caret) = Panel.inserting("[Chorus]", into: words.text, at: words.caret)
        words.redraw()
        #expect(view.string == out)
        #expect(view.selectedRange() == NSRange(location: Panel.utf16Offset(ofCharacter: outCaret, in: out), length: 0))
        #expect(words.text == out && words.caret == outCaret)
    }

    /// Needs a window server session: `undo:` is answered by the window, as
    /// in the popover. The window is never shown.
    @Test("Undo, sent down the responder chain, takes back a mark the panel inserted, and is reported; the window keeps none of it")
    func undo() throws {
        let words = Words("abcdef", caret: 3)
        let window = NSWindow(contentRect: words.host.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = words.host
        words.host.layoutSubtreeIfNeeded()
        let view = try words.view
        (words.text, words.caret) = Panel.inserting("[Chorus]", into: words.text, at: words.caret)
        words.redraw()
        #expect(view.string == "abc\n[Chorus]\ndef")
        #expect(window.makeFirstResponder(view))
        #expect(view.tryToPerform(Selector(("undo:")), with: nil))
        #expect(view.string == "abcdef")
        #expect(words.text == "abcdef")
        #expect(view.tryToPerform(Selector(("redo:")), with: nil))
        #expect(words.text == "abc\n[Chorus]\ndef")
        #expect(window.undoManager?.canUndo == false)
    }

    @Test("Tab and Shift-Tab are not typed")
    func tab() throws {
        let words = Words("ab", caret: 2)
        let view = try words.view
        let delegate = try #require(view.delegate)
        #expect(delegate.textView?(view, doCommandBy: #selector(NSResponder.insertTab(_:))) == true)
        #expect(delegate.textView?(view, doCommandBy: #selector(NSResponder.insertBacktab(_:))) == true)
        #expect(delegate.textView?(view, doCommandBy: #selector(NSResponder.insertNewline(_:))) == false)
        #expect(view.string == "ab")
    }
}

@Suite("ScrollBox")
@MainActor
struct ScrollBoxTests {
    /// Rows 48 pt tall and 6 apart, as in the queue card, in a box 300 wide
    /// and 340 tall.
    private func box(_ rows: Int) throws -> FadingScrollView {
        let host = NSHostingView(rootView: ScrollBox {
            VStack(spacing: 6) {
                ForEach(0..<rows, id: \.self) { i in Text(verbatim: "Row \(i)").frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48) }
            }
        }
        .frame(width: 300, height: 340))
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 340)
        host.layoutSubtreeIfNeeded()
        let scroll = try #require(find(FadingScrollView.self, in: host))
        scroll.layoutSubtreeIfNeeded()
        return scroll
    }

    @Test("the document is as wide as the box and as tall as its rows; an edge fades only while more lies beyond it",
          arguments: [3, 12, 50])
    func sizing(_ rows: Int) throws {
        let scroll = try box(rows)
        let document = try #require(scroll.documentView)
        let height = CGFloat(rows * 54 - 6)
        #expect(document.frame.width == scroll.contentSize.width)
        #expect(scroll.contentSize.width == 300)
        #expect(document.frame.height == height)
        #expect((scroll.layer?.mask != nil) == (height > 340))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, height - 340)))
        scroll.reflectScrolledClipView(scroll.contentView)
        // At the end the top edge fades instead, while there is more above.
        #expect((scroll.layer?.mask != nil) == (height > 340))
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        #expect((scroll.layer?.mask != nil) == (height > 340))
    }

    /// Whether the top and the bottom edge are faded, by the mask's alpha.
    private func faded(_ scroll: FadingScrollView) throws -> (top: Bool, bottom: Bool) {
        let mask = try #require(scroll.layer?.mask as? CAGradientLayer)
        let colors = try #require(mask.colors as? [CGColor])
        return (colors[0].alpha == 0, colors[3].alpha == 0)
    }

    @Test("a round of 100: the document is 100 rows tall; top and bottom are reached and never passed, the last row whole")
    func hundred() throws {
        let scroll = try box(100)
        let document = try #require(scroll.documentView)
        let height = CGFloat(100 * 54 - 6)
        #expect(document.frame.height == height)
        #expect(try faded(scroll) == (false, true))

        scroll.scroll(toY: .greatestFiniteMagnitude, animated: false)
        let visible = scroll.contentView.documentVisibleRect
        #expect(visible.minY == height - 340 && visible.maxY == height)
        #expect(visible.contains(CGRect(x: 0, y: CGFloat(99 * 54), width: 300, height: 48)))
        #expect(try faded(scroll) == (true, false))

        scroll.scroll(toY: CGFloat(50 * 54), animated: false)
        #expect(scroll.contentView.bounds.minY == CGFloat(50 * 54))
        #expect(try faded(scroll) == (true, true))

        scroll.scroll(toY: -100, animated: false)
        #expect(scroll.contentView.bounds.minY == 0)
        #expect(try faded(scroll) == (false, true))
    }
}

@Suite("Main menu")
@MainActor
struct MainMenuTests {
    @Test("the Edit menu sends the standard actions down the responder chain, with their key equivalents")
    func edit() throws {
        let main = makeMainMenu()
        let edit = try #require(main.items.first { $0.submenu?.title == "Edit" }?.submenu)
        let items = edit.items.filter { !$0.isSeparatorItem }
        let expected: [(String, String, String, NSEvent.ModifierFlags)] = [
            ("Undo", "undo:", "z", .command),
            ("Redo", "redo:", "z", [.command, .shift]),
            ("Cut", "cut:", "x", .command),
            ("Copy", "copy:", "c", .command),
            ("Paste", "paste:", "v", .command),
            ("Delete", "delete:", "", .command),
            ("Select All", "selectAll:", "a", .command),
        ]
        #expect(items.count == expected.count)
        for (item, (title, action, key, modifiers)) in zip(items, expected) {
            #expect(item.title == title)
            #expect(item.action.map(NSStringFromSelector) == action)
            #expect(item.keyEquivalent == key)
            #expect(key.isEmpty || item.keyEquivalentModifierMask == modifiers)
            #expect(item.target == nil)
        }
    }

    @Test("the app menu quits, with no key equivalent")
    func app() throws {
        let app = try #require(makeMainMenu().items.first?.submenu)
        #expect(app.items.map(\.title) == ["Quit SwiftTunes"])
        #expect(app.items.first?.action == #selector(NSApplication.terminate(_:)))
        #expect(app.items.first?.keyEquivalent == "")
    }
}

@Suite("Pasting words")
@MainActor
struct PasteTests {
    /// Fixture 36: a sung genre playing.
    private func sung() throws -> TunesContract.Snapshot {
        let file = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "TunesPanelTests/Fixtures/36-sung-lyrics.jsonl")
        let options = try #require(DemoOptions(arguments: ["SwiftTunes", "--demo", file.path]))
        return DemoEngine(options: options).snapshot
    }

    @Test("the text view is editable and selectable, and its contextual menu offers Cut, Copy and Paste")
    func menu() throws {
        let view = try Words("ab", caret: 2).view
        #expect(view.isEditable && view.isSelectable)
        let click = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                    windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let actions = try #require(view.menu(for: click)).items.compactMap(\.action).map(NSStringFromSelector)
        #expect(Set(["cut:", "copy:", "paste:"]).isSubset(of: actions))
    }

    /// Reads a private pasteboard, as `paste:` reads the general one, so the
    /// test never touches the user's clipboard.
    @Test("styled text pastes as plain text in the editor's font, and reaches the words and the counter")
    func paste() throws {
        let words = Words("", caret: 0)
        let view = try words.view
        let board = NSPasteboard(name: NSPasteboard.Name("SwiftTunesTests.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        let styled = NSAttributedString(string: "Line one\nLine two", attributes: [
            .font: NSFont.boldSystemFont(ofSize: 30), .foregroundColor: NSColor.systemRed, .underlineStyle: 1,
        ])
        #expect(board.writeObjects([styled]))
        #expect(view.readSelection(from: board))

        #expect(view.string == "Line one\nLine two")
        let storage = try #require(view.textStorage)
        var runs = 0
        storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { attributes, _, _ in
            runs += 1
            #expect(attributes[.font] as? NSFont == NSFont.systemFont(ofSize: 13))
            #expect(attributes[.underlineStyle] == nil)
            #expect(attributes[.foregroundColor] as? NSColor != NSColor.systemRed)
        }
        #expect(runs == 1)
        #expect(words.text == "Line one\nLine two" && words.caret == 17)

        let s = try sung()
        let panel = Panel().openingWords(s, name: "Long Way Home").typedWords(words.text, caret: words.caret)
        guard case .words(let card) = Decide.card(s, panel, now: 0, home: "/") else { Issue.record("not the sheet"); return }
        #expect(card.counter == "2 sung lines · 17 of 2,000 characters")
    }
}

@Suite("ScrollBox follows the playing row")
@MainActor
struct ScrollFollowTests {
    /// `rows` 48 pt rows, 6 apart, in a box four rows tall.
    private func host(playing: Int?, rows: Int = 50) -> NSHostingView<AnyView> {
        let host = NSHostingView(rootView: view(playing: playing, rows: rows))
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 210)
        host.layoutSubtreeIfNeeded()
        return host
    }

    private func view(playing: Int?, rows: Int = 50) -> AnyView {
        let ids = (0..<rows).map { "row \($0)" }
        return AnyView(ScrollBox(follow: ScrollFollow(ids: ids, playing: playing)) {
            VStack(spacing: 6) {
                ForEach(ids, id: \.self) { id in
                    Text(verbatim: id).frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48).scrollMark(id)
                }
            }
        }
        .frame(width: 300, height: 210))
    }

    private func scroll(_ host: NSView) throws -> FadingScrollView {
        let scroll = try #require(find(FadingScrollView.self, in: host))
        scroll.layoutSubtreeIfNeeded()
        return scroll
    }

    @Test("on first showing, the playing row is placed second from the top", arguments: [(40, 39), (0, 0), (1, 0), (49, 46)])
    func opens(_ playing: Int, _ top: Int) throws {
        let s = try scroll(host(playing: playing))
        #expect(s.contentView.bounds.minY == CGFloat(top * 54))
    }

    @Test("a round of 100: the playing row second from the top, or as near as the end allows; it is always whole in view",
          arguments: [(0, 0), (1, 0), (2, 1), (49, 48), (97, 96), (99, 96)])
    func hundred(_ playing: Int, _ top: Int) throws {
        let s = try scroll(host(playing: playing, rows: 100))
        #expect(s.contentView.bounds.minY == CGFloat(top * 54))
        #expect(s.contentView.documentVisibleRect.contains(CGRect(x: 0, y: CGFloat(playing * 54), width: 300, height: 48)))
        #expect(s.contentView.bounds.maxY <= CGFloat(100 * 54 - 6))
    }

    @Test("nothing playing: the list stays at the top")
    func idle() throws {
        #expect(try scroll(host(playing: nil)).contentView.bounds.minY == 0)
    }

    @Test("the same playing row again does not pull back a list the user moved")
    func sameTune() throws {
        let h = host(playing: 40)
        let s = try scroll(h)
        s.contentView.scroll(to: NSPoint(x: 0, y: 108))
        s.reflectScrolledClipView(s.contentView)
        h.rootView = view(playing: 40)
        h.layoutSubtreeIfNeeded()
        #expect(s.contentView.bounds.minY == 108)
    }

    @Test("with the pointer over the list, a change of tune leaves it where it is")
    func pointerOver() throws {
        let h = host(playing: 40)
        let s = try scroll(h)
        let enter = try #require(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                                       context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
        s.mouseEntered(with: enter)
        h.rootView = view(playing: 10)
        h.layoutSubtreeIfNeeded()
        #expect(s.contentView.bounds.minY == CGFloat(39 * 54))
    }
}

@Suite("Demo round")
@MainActor
struct DemoRoundTests {
    private func demo() throws -> DemoEngine {
        let file = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "TunesPanelTests/Fixtures/45-round-played.jsonl")
        return DemoEngine(options: try #require(DemoOptions(arguments: ["SwiftTunes", "--demo", file.path])))
    }

    private func numbers(_ s: TunesContract.Snapshot) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: Decide.round(played: s.played, tune: s.tune, queue: s.queue).map { ($0.file, $0.number) })
    }

    @Test("next, then previous within 3 s: the round walks and comes back, no number moving")
    func walk() throws {
        let engine = try demo()
        let before = numbers(engine.snapshot)
        #expect(engine.snapshot.tune?.name == "Lazy Avenue")
        engine.send(.next)
        #expect(engine.snapshot.tune?.name == "Smoky Lounge" && engine.snapshot.played.count == 5)
        #expect(numbers(engine.snapshot) == before)
        engine.send(.previous)
        #expect(engine.snapshot.tune?.name == "Lazy Avenue" && engine.snapshot.queue.first?.name == "Smoky Lounge")
        #expect(numbers(engine.snapshot) == before)
    }

    @Test("previous more than 3 s in restarts the tune")
    func restart() throws {
        let engine = try demo()
        engine.send(.previous)
        #expect(engine.snapshot.tune?.name == "Lazy Avenue" && engine.snapshot.played.count == 4 && engine.snapshot.pos == 0)
    }

    @Test("play it again: that tune plays, the ones after it wait again in list order")
    func again() throws {
        let engine = try demo()
        let before = numbers(engine.snapshot)
        engine.send(.playPlayed(index: 1, name: "Blue Avenue"))
        let s = engine.snapshot
        #expect(s.tune?.name == "Blue Avenue" && s.played.map(\.name) == ["Late Lounge"])
        #expect(s.queue.prefix(4).map(\.name) == ["Smoky Martini", "Easy Lounge", "Lazy Avenue", "Smoky Lounge"])
        #expect(numbers(s) == before)
    }

    @Test("a command whose name no longer matches does nothing")
    func stale() throws {
        let engine = try demo()
        let before = engine.snapshot
        engine.send(.playPlayed(index: 1, name: "Late Lounge"))
        engine.send(.scrapPlayed(index: 0, name: "Blue Avenue"))
        #expect(engine.snapshot == before)
        engine.send(.scrapPlayed(index: 0, name: "Late Lounge"))
        #expect(engine.snapshot.played.map(\.name) == ["Blue Avenue", "Smoky Martini", "Easy Lounge"])
    }
}

@Suite("Demo models")
@MainActor
struct DemoModelsTests {
    private func demo(_ name: String, open: String? = nil) throws -> DemoEngine {
        let file = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "TunesPanelTests/Fixtures/\(name).jsonl")
        return DemoEngine(options: try #require(DemoOptions(arguments: ["SwiftTunes", "--demo", file.path])))
    }

    /// The demo over `name`'s last snapshot changed by `change`, read from a
    /// file of its own that is removed once read.
    private func demo(_ name: String, _ change: (inout Snapshot) -> Void) throws -> DemoEngine {
        var s = try demo(name).snapshot
        change(&s)
        let file = FileManager.default.temporaryDirectory.appending(path: "demo-models-\(UUID().uuidString).jsonl")
        try JSONEncoder().encode(s).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        return DemoEngine(options: try #require(DemoOptions(arguments: ["SwiftTunes", "--demo", file.path])))
    }

    @Test("--demo-open models opens the models card")
    func open() throws {
        let options = try #require(DemoOptions(arguments: ["SwiftTunes", "--demo", "x.jsonl", "--demo-open", "models"]))
        guard case .models? = options.open else { Issue.record("not models: \(String(describing: options.open))"); return }
    }

    @Test("Use: that model is chosen, its variant and memory figure the composer's")
    func use() throws {
        let engine = try demo("51-models-both-large-chosen")
        engine.send(.chooseModel(id: "small"))
        let s = engine.snapshot
        #expect(s.models.map(\.chosen) == [true, false])
        #expect(s.model.variant == "0.6B Q8" && s.need.ramBytes == 4 << 30)
    }

    @Test("choosing a model not on disk while another is: nothing")
    func useNotOnDisk() throws {
        let engine = try demo("50-models-large-only")
        let before = engine.snapshot
        engine.send(.chooseModel(id: "small"))
        #expect(engine.snapshot == before)
    }

    @Test("the first run: a click on a row chooses it, and the download follows it")
    func firstRun() throws {
        let engine = try demo("48-models-first-16gib")
        engine.send(.chooseModel(id: "large"))
        #expect(engine.snapshot.models.map(\.chosen) == [false, true])
        #expect(engine.snapshot.need.downloadBytes == 8_128_417_536)
    }

    @Test("Download, then Cancel: the row downloads, then offers Download again")
    func downloadCancel() throws {
        let engine = try demo("50-models-large-only")
        engine.send(.downloadModel(id: "small"))
        #expect(engine.snapshot.models[0].downloading && engine.snapshot.download?.model == "small")
        #expect(engine.snapshot.setup == .ready)
        engine.send(.cancelDownload)
        #expect(!engine.snapshot.models[0].downloading && engine.snapshot.download == nil)
    }

    @Test("Remove one of two: its file goes, the shared files stay")
    func removeOne() throws {
        let engine = try demo("51-models-both-large-chosen")
        engine.send(.removeOneModel(id: "small"))
        let s = engine.snapshot
        #expect(!s.models[0].onDisk && s.models[0].downloadBytes == 709_846_656)
        #expect(s.need.onDiskBytes == 8_128_417_536 && s.setup == .ready)
    }

    @Test("the chosen one while another is on disk: nothing")
    func removeChosen() throws {
        let engine = try demo("51-models-both-large-chosen")
        let before = engine.snapshot
        engine.send(.removeOneModel(id: "large"))
        #expect(engine.snapshot == before)
    }

    @Test("the only one on disk: removed as the music model, shared files and all")
    func removeLast() throws {
        let engine = try demo("50-models-large-only")
        engine.send(.removeOneModel(id: "large"))
        let s = engine.snapshot
        #expect(s.setup == .missing && s.need.onDiskBytes == 0 && !s.composing)
        #expect(s.models.map(\.onDisk) == [false, false])
        #expect(s.models.map(\.downloadBytes) == [4_380_940_544, 8_128_417_536])
        #expect(s.need.downloadBytes == 8_128_417_536)
    }

    /// Large on disk and a 300,000,000-byte part of Small.
    private func smallPart(_ s: inout Snapshot) {
        s.models[0].downloadBytes -= 300_000_000
        s.need.onDiskBytes += 300_000_000
    }

    @Test("Remove on a part beside a complete model: the part goes, nothing else")
    func removePart() throws {
        let engine = try demo("50-models-large-only", smallPart)
        engine.send(.removeOneModel(id: "small"))
        let s = engine.snapshot
        #expect(s.models[0].downloadBytes == 709_846_656 && !s.models[0].onDisk)
        #expect(s.models[1].onDisk && s.need.onDiskBytes == 8_128_417_536 && s.setup == .ready)
    }

    @Test("Remove on a part with no model complete: everything goes")
    func removePartAlone() throws {
        let engine = try demo("49-models-first-64gib") { s in
            s.models[1].downloadBytes -= 4_000_000_000
            s.models[0].downloadBytes -= 3_671_093_888
            s.need.downloadBytes = s.models[1].downloadBytes
            s.need.onDiskBytes = 4_000_000_000
        }
        engine.send(.removeOneModel(id: "small"))
        let s = engine.snapshot
        #expect(s.need.onDiskBytes == 0 && s.setup == .missing)
        #expect(s.models.map(\.downloadBytes) == [4_380_940_544, 8_128_417_536])
    }

    @Test("removing the last model counts the shared files from sharedBytes, not from what is left on disk")
    func removeLastWithPart() throws {
        let engine = try demo("50-models-large-only", smallPart)
        engine.send(.removeOneModel(id: "large"))
        #expect(engine.snapshot.models.map(\.downloadBytes) == [4_380_940_544, 8_128_417_536])
    }

    @Test("Resume on a failed second download fetches that model again")
    func resumeFailed() throws {
        let engine = try demo("53-models-second-failed")
        engine.send(.downloadModel(id: "small"))
        let s = engine.snapshot
        #expect(s.models[0].downloading && s.download?.model == "small" && s.download?.error == nil && s.setup == .ready)
    }

    @Test("Resume on a part fetches what is left of it")
    func resumePart() throws {
        let engine = try demo("50-models-large-only", smallPart)
        engine.send(.downloadModel(id: "small"))
        #expect(engine.snapshot.download?.total == 409_846_656 && engine.snapshot.download?.files == 1)
    }
}
