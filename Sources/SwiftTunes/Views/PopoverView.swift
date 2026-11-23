import SwiftUI
import TunesContract
import TunesPanel

/// The popover's content: the one card `TunesPanel` chooses, and the footer.
struct PopoverView: View {
    let model: PanelModel

    var body: some View {
        VStack(spacing: 0) {
            switch model.card {
            case .setup(let c): SetupView(card: c, model: model)
            case .chooser(let c): ChooserView(card: c, model: model)
            case .editor(let c): EditorView(card: c, model: model)
            case .share(let c): ShareView(card: c, model: model)
            case .player(let c): PlayerView(card: c, model: model)
            }
            if let footer = model.footer {
                FooterView(footer: footer, model: model)
            }
        }
        .frame(width: 380)
        .font(.system(size: 13))
        .monospacedDigit()
    }
}

struct FooterView: View {
    let footer: Footer
    let model: PanelModel

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                switch footer {
                case .notice(let text):
                    Text(verbatim: text).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                case .undo(let text, let button):
                    Text(verbatim: text).foregroundStyle(.orange).lineLimit(1)
                    Spacer(minLength: 0)
                    PushButton(control: button, action: model.undo)
                }
            }
            .font(.system(size: 11))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
    }
}

// MARK: - Shared pieces

/// A section heading in small capitals with its right-hand side.
struct SectionHeading<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: title)
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            trailing
        }
    }
}

/// A text button drawn as the draft's pill.
struct PushButton: View {
    let control: Control
    var prominent = false
    var destructive = false
    let action: () -> Void

    var body: some View {
        if prominent {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private var button: some View {
        Button(action: action) {
            Text(verbatim: control.text)
                .foregroundStyle(destructive ? AnyShapeStyle(.red) : AnyShapeStyle(prominent ? .white : .primary))
        }
        .controlSize(.small)
        .disabled(!control.enabled)
        .help(control.help)
        .accessibilityLabel(Text(verbatim: control.help))
    }
}

/// An icon button with the control's state: dimmed when it cannot act,
/// tinted when its mode is on.
struct IconButton: View {
    let symbol: String
    let control: Control
    var wide = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                if !control.text.isEmpty {
                    Text(verbatim: control.text).font(.system(size: 12))
                }
            }
            .frame(minWidth: wide ? 32 : 18, minHeight: 18)
            .foregroundStyle(control.lit ? Color.accentColor : .primary)
        }
        .buttonStyle(.bordered)
        .tint(control.lit ? .accentColor : nil)
        .disabled(!control.enabled)
        .opacity(control.enabled ? 1 : 0.4)
        .help(control.help)
        .accessibilityLabel(Text(verbatim: control.help))
    }
}

/// "‹ Jazz", the way back.
struct BackLink: View {
    let control: Control
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: "‹ \(control.text)").foregroundStyle(Color(nsColor: .linkColor))
        }
        .buttonStyle(.plain)
        .font(.system(size: 12.5))
        .help(control.help)
        .accessibilityLabel(Text(verbatim: control.help))
    }
}

/// The engine's error line, drawn as plain text.
struct Strip: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 11.5))
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
