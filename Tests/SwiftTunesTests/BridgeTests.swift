import AppKit
import SwiftUI
import Testing
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

    /// Needs a window server session: a text view takes its undo manager
    /// from its window, as in the popover. The window is never shown.
    @Test("a mark inserted by the panel is undone by the window's undo, and the undone text is reported")
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
        let undo = try #require(view.undoManager)
        #expect(undo.canUndo)
        undo.undo()
        #expect(view.string == "abcdef")
        #expect(words.text == "abcdef")
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
