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

    @Test("the document is as wide as the box and as tall as its rows; the bottom fades only while more lies below",
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
        #expect(scroll.layer?.mask == nil)
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
