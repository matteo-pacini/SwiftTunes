import SwiftUI
import TunesPanel

/// A genre's colour field: a 3 × 3 mesh of its palette whose inner points
/// drift while the popover is open and motion is allowed.
struct Backdrop: View {
    let palette: Palette
    @Environment(\.colorScheme) private var scheme
    @Environment(\.motion) private var motion

    var body: some View {
        let field = palette.field(dark: scheme == .dark).map(\.color)
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !motion.drifts)) { context in
            let t = motion.drifts ? context.date.timeIntervalSinceReferenceDate : 0
            MeshGradient(width: 3, height: 3, points: Self.points(at: t), colors: Self.colors(field))
        }
    }

    /// Edges stay on the frame; the middle row and column sway slowly.
    static func points(at t: Double) -> [SIMD2<Float>] {
        func s(_ speed: Double, _ phase: Double, _ amount: Double) -> Float { Float(amount * sin(t * speed + phase)) }
        return [
            [0, 0], [0.5 + s(0.11, 0, 0.18), 0], [1, 0],
            [0, 0.5 + s(0.09, 1, 0.2)], [0.5 + s(0.13, 2, 0.22), 0.5 + s(0.1, 3, 0.2)], [1, 0.5 + s(0.12, 4, 0.2)],
            [0, 1], [0.5 + s(0.08, 5, 0.18), 1], [1, 1],
        ]
    }

    /// The base colour at the corners and edges, the three lights inside.
    static func colors(_ c: [Color]) -> [Color] {
        guard c.count == 4 else { return Array(repeating: .black, count: 9) }
        return [c[1], c[0], c[2], c[0], c[0], c[2], c[3], c[3], c[0]]
    }
}
