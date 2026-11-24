import AppKit
import SwiftUI
import TunesPanel

// SwiftUI's own scrolling and text views stall the main thread inside the
// renderer when hosted in the popover; these are the AppKit stand-ins
// (AGENTS.md, "No SwiftUI ScrollView, List, Form or TextEditor").

/// SwiftUI rows in a vertical `NSScrollView`: transparent, with overlay
/// scrollers, the rows as wide as the box and as tall as they need, and the
/// bottom edge faded while more lies below it. The caller sets the box's
/// height.
///
/// With a `target`, the row marked `.scrollMark(target)` is brought into
/// view when the box first shows it and each time the target changes; the
/// user's own scrolling is left alone otherwise.
struct ScrollBox<Content: View>: NSViewRepresentable {
    var target: String? = nil
    @ViewBuilder let content: Content

    func makeCoordinator() -> ScrollMarks { ScrollMarks() }

    func makeNSView(context: Context) -> FadingScrollView {
        let scroll = FadingScrollView()
        let marks = context.coordinator
        scroll.documentView = ScrollDocument(rootView: Fitted(marks: marks, content: content))
        marks.scroll = scroll
        return scroll
    }

    func updateNSView(_ scroll: FadingScrollView, context: Context) {
        guard let document = scroll.documentView as? ScrollDocument<Content> else { return }
        document.rootView = Fitted(width: document.rootView.width, marks: context.coordinator, content: content)
        scroll.tile()
        context.coordinator.target = target
        context.coordinator.reveal()
    }
}

/// Where the marked rows sit in a scroll box's document, and the row to
/// bring into view.
final class ScrollMarks {
    nonisolated static let space = "ScrollBox"
    weak var scroll: NSScrollView?
    var frames: [String: CGRect] = [:]
    var target: String?
    /// The target last brought into view; a new target is revealed once.
    private var revealed: String?

    func reveal() {
        guard let target, target != revealed, let frame = frames[target], let document = scroll?.documentView,
              document.frame.height >= frame.maxY else { return }
        revealed = target
        // Half a row of margin, so the rows either side show they continue.
        _ = document.scrollToVisible(frame.insetBy(dx: 0, dy: -frame.height / 2))
    }
}

extension EnvironmentValues {
    @Entry var scrollMarks: ScrollMarks?
}

extension View {
    /// Marks this row in the enclosing scroll box, so the box can bring it
    /// into view by `id`.
    func scrollMark(_ id: String) -> some View {
        modifier(ScrollMark(id: id))
    }
}

private struct ScrollMark: ViewModifier {
    let id: String
    @Environment(\.scrollMarks) private var marks

    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGRect.self) { $0.frame(in: .named(ScrollMarks.space)) } action: { frame in
            guard let marks else { return }
            marks.frames[id] = frame
            if id == marks.target { marks.reveal() }
        }
    }
}

/// The rows at the width the scroll box gives them, so their height can be
/// measured at that width.
struct Fitted<Content: View>: View {
    var width: CGFloat?
    var marks: ScrollMarks?
    let content: Content

    var body: some View {
        content
            .frame(width: width, alignment: .topLeading)
            .coordinateSpace(.named(ScrollMarks.space))
            .environment(\.scrollMarks, marks)
    }
}

/// A scroll box's document: the rows, sized by their content.
final class ScrollDocument<Content: View>: NSHostingView<Fitted<Content>>, FitsWidth {
    required init(rootView: Fitted<Content>) {
        super.init(rootView: rootView)
        // Its frame is set by `fit(width:)`; min and max constraints would
        // only fight the frame the scroll view's autoresizing gives it.
        sizingOptions = [.intrinsicContentSize]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func fit(width: CGFloat) {
        if rootView.width != width { rootView.width = width }
        let size = NSSize(width: width, height: ceil(fittingSize.height))
        if frame.size != size { setFrameSize(size) }
    }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        enclosingScrollView?.needsLayout = true
    }
}

protocol FitsWidth: NSView {
    func fit(width: CGFloat)
}

/// A transparent vertical scroll view whose document fills its width, with
/// the bottom edge faded while there is more below it.
final class FadingScrollView: NSScrollView {
    private static let fade: CGFloat = 18
    private let fadeMask = CAGradientLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        drawsBackground = false
        contentView.drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        scrollerStyle = .overlay
        wantsLayer = true
        fadeMask.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func tile() {
        super.tile()
        (documentView as? any FitsWidth)?.fit(width: contentSize.width)
        updateFade()
    }

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        updateFade()
    }

    private func updateFade() {
        guard let layer, let document = documentView else { return }
        let below = document.frame.height - contentView.bounds.maxY
        guard below > 1, bounds.height > Self.fade else {
            if layer.mask != nil { layer.mask = nil }
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fadeMask.frame = layer.bounds
        // Unit coordinates follow the layer's geometry: y grows upwards
        // unless the geometry is flipped.
        let top: CGFloat = layer.isGeometryFlipped ? 0 : 1
        fadeMask.startPoint = CGPoint(x: 0.5, y: top)
        fadeMask.endPoint = CGPoint(x: 0.5, y: 1 - top)
        fadeMask.locations = [0, NSNumber(value: Double(1 - Self.fade / bounds.height)), 1]
        if layer.mask !== fadeMask { layer.mask = fadeMask }
        CATransaction.commit()
    }
}

/// Plain multi-line text in an `NSTextView`: no rich text, no smart quotes,
/// dashes or other substitutions, and an undo history of its own.
///
/// The caller owns the text: `changed` reports each edit and each caret
/// move as the whole text and the caret (in characters, at the end of the
/// selection). A `text` or `caret` that differs from what the view holds is
/// applied as an undoable edit and a caret move; one equal to it changes
/// nothing, so a value the view itself reported never moves the caret.
/// Tab and Shift-Tab move the focus instead of typing a tab.
struct PlainTextEditor: NSViewRepresentable {
    let text: String
    /// Where the caret should be, in characters; nil leaves it where it is.
    var caret: Int? = nil
    var fontSize: CGFloat = 13
    let label: String
    let changed: (_ text: String, _ caret: Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        guard let view = scroll.documentView as? NSTextView else { return scroll }
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.usesFindBar = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isAutomaticDataDetectionEnabled = false
        view.isAutomaticTextCompletionEnabled = false
        view.smartInsertDeleteEnabled = false
        view.drawsBackground = false
        view.font = .systemFont(ofSize: fontSize)
        view.textColor = .labelColor
        view.string = text
        view.setAccessibilityLabel(label)
        context.coordinator.view = view
        if let caret { context.coordinator.place(caret) }
        // Attached last: the caller's own caret is not reported back to it.
        view.delegate = context.coordinator
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.apply(text: text, caret: caret)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PlainTextEditor
        weak var view: NSTextView?
        /// Set while the caller's values are applied, so the view's own
        /// notifications are not reported back as edits during a view update.
        private var applying = false
        /// Not the window's: the popover's window outlives the card, and its
        /// undo manager would keep this view's edits after the view is gone,
        /// for Command-Z to replay into it.
        private let undo = UndoManager()

        init(_ parent: PlainTextEditor) { self.parent = parent }

        func apply(text: String, caret: Int?) {
            guard let view else { return }
            applying = true
            defer { applying = false }
            if view.string != text { replace(in: view, with: text) }
            if let caret, caret != self.caret(in: view) { place(caret) }
        }

        /// Only the span that differs is replaced, so undo restores just
        /// that span and text before it keeps its place.
        private func replace(in view: NSTextView, with text: String) {
            let old = view.string as NSString
            let new = text as NSString
            var start = 0
            while start < old.length, start < new.length, old.character(at: start) == new.character(at: start) { start += 1 }
            var end = 0
            while end < old.length - start, end < new.length - start,
                  old.character(at: old.length - 1 - end) == new.character(at: new.length - 1 - end) { end += 1 }
            let range = NSRange(location: start, length: old.length - start - end)
            let insert = new.substring(with: NSRange(location: start, length: new.length - start - end))
            guard view.shouldChangeText(in: range, replacementString: insert) else { return }
            view.replaceCharacters(in: range, with: insert)
            view.didChangeText()
        }

        func place(_ caret: Int) {
            guard let view else { return }
            let at = Panel.utf16Offset(ofCharacter: caret, in: view.string)
            view.setSelectedRange(NSRange(location: at, length: 0))
            view.scrollRangeToVisible(NSRange(location: at, length: 0))
        }

        private func caret(in view: NSTextView) -> Int {
            Panel.characterOffset(ofUTF16: NSMaxRange(view.selectedRange()), in: view.string)
        }

        private func report() {
            guard !applying, let view else { return }
            parent.changed(view.string, caret(in: view))
        }

        func undoManager(for view: NSTextView) -> UndoManager? { undo }

        func textDidChange(_ notification: Notification) { report() }
        func textViewDidChangeSelection(_ notification: Notification) { report() }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertTab(_:)):
                textView.window?.selectNextKeyView(nil)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                textView.window?.selectPreviousKeyView(nil)
                return true
            default:
                return false
            }
        }
    }
}
