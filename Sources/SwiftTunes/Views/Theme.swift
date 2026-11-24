import AppKit
import SwiftUI
import TunesPanel

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

    /// The system's bright tones lose contrast on a light field; these keep
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

extension RGB {
    var color: Color { Color(.sRGB, red: r, green: g, blue: b) }

    /// The colour a colour well picked, as sRGB.
    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent))
    }
}

extension Palette {
    /// The field behind the setup cards and the chooser: no genre's colours.
    static let neutral = Palette(colors: [RGB(0.09, 0.09, 0.11), RGB(0.17, 0.17, 0.21), RGB(0.13, 0.13, 0.17), RGB(0.11, 0.11, 0.15)])
}

/// What may move, as `Decide.animating` says for the card showing.
struct Motion: Equatable {
    /// The colour field.
    var drifts = false
    /// The forming waves.
    var forms = false
    /// The playing row's level meter.
    var meters = false
}

extension EnvironmentValues {
    @Entry var motion = Motion()
}

/// The words of a control's tooltip and accessibility label.
extension View {
    func helped(_ control: Control) -> some View {
        help(control.help).accessibilityLabel(Text(verbatim: control.help))
    }
}
