import SwiftUI
import TunesContract
import TunesPanel

/// The popover's content: the colour field, the one card `TunesPanel`
/// chooses on it, and the footer as a glass toast.
struct PopoverView: View {
    let model: PanelModel
    @Namespace private var space
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let card = model.card
        ZStack(alignment: .bottom) {
            backdrop(card)
            content(card)
                .padding(16)
                .padding(.bottom, model.footer == nil ? 0 : 50)
            if let footer = model.footer {
                Toast(footer: footer, model: model)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: 380)
        .font(.system(size: 13))
        .monospacedDigit()
        .environment(\.motion, Motion(open: model.isOpen, reduce: reduceMotion, lowPower: model.lowPower))
        .animation(reduceMotion ? nil : .spring(duration: 0.4), value: model.footer)
        .onExitCommand(perform: model.escape)
    }

    @ViewBuilder private func backdrop(_ card: Card) -> some View {
        switch card {
        case .player(let p):
            Backdrop(palette: p.palette)
                .matchedGeometryEffect(id: model.snapshot.genre ?? "", in: space, isSource: false)
        case .share, .editor, .queue:
            Backdrop(palette: Decide.palette(model.snapshot))
        case .setup, .chooser:
            Backdrop(palette: .neutral)
        }
    }

    @ViewBuilder private func content(_ card: Card) -> some View {
        switch card {
        case .setup(let c): SetupView(card: c, model: model)
        case .chooser(let c): ChooserView(card: c, model: model, space: space)
        case .editor(let c): EditorView(card: c, model: model)
        case .share(let c): ShareView(card: c, model: model)
        case .player(let c): PlayerView(card: c, model: model)
        case .queue(let c): QueueView(card: c, model: model)
        }
    }
}

/// The undo line or a notice, floating over the bottom edge.
struct Toast: View {
    let footer: Footer
    let model: PanelModel

    var body: some View {
        HStack(spacing: 8) {
            switch footer {
            case .notice(let text):
                Text(verbatim: text).lineLimit(2)
                Spacer(minLength: 0)
            case .undo(let text, let button):
                Text(verbatim: text).lineLimit(1)
                Spacer(minLength: 0)
                Button(action: model.undo) {
                    Text(verbatim: button.text)
                        .contentTransition(.numericText(countsDown: true))
                }
                .buttonStyle(.glassProminent)
                .controlSize(.small)
                .helped(button)
            }
        }
        .font(.system(size: 12.5))
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 7)
        .frame(minHeight: 36)
        .glassEffect(.regular, in: .rect(cornerRadius: 13))
    }
}

// MARK: - Shared pieces

/// A small-capitals label.
struct Caps: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}

/// A round glass control: dimmed when it cannot act, brighter when its
/// mode is on.
struct RoundButton: View {
    let symbol: String
    let control: Control
    var size: Double = 34
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: size, height: size)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(control.lit ? .regular.tint(.white.opacity(0.3)).interactive() : .regular.interactive(), in: .circle)
        .disabled(!control.enabled)
        .opacity(control.enabled ? 1 : 0.38)
        .helped(control)
    }
}

/// "‹ Jazz": the way back, a glass capsule.
struct BackLink: View {
    let control: Control
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                Text(verbatim: control.text)
            }
            .font(.system(size: 12.5, weight: .semibold))
            .padding(.horizontal, 11)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .helped(control)
    }
}

/// A count or state in a small capsule.
struct Pill: View {
    let text: String
    var tone: Tone = .normal

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 11.5))
            .foregroundStyle(tone == .dim || tone == .soft ? Tone.normal.color : tone.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(.black.opacity(0.18), in: .capsule)
    }
}

/// The engine's error line, drawn as plain text.
struct Strip: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 11.5))
            .foregroundStyle(Tone.orange.color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
