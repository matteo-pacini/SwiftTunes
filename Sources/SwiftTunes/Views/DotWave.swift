import SwiftUI
import TunesContract
import TunesPanel

/// The tune's shape as mirrored columns of dots, lit up to the played
/// part; or, with a stage, the forming wave, which moves by stage only.
struct DotWave: View {
    /// Levels in 0…1, one per column.
    var levels: [Double]
    var played: Int = 0
    var forming: JobStage?
    /// Columns of the forming wave.
    var columns: Int = Decide.waveBars
    var dot: Color
    var lit: Color

    @Environment(\.motion) private var motion

    var body: some View {
        if let forming {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !motion.forms)) { context in
                let t = motion.forms ? context.date.timeIntervalSinceReferenceDate : 2.3
                canvas { i, n in Forming.level(column: i, of: n, at: t, stage: forming) }
            }
        } else {
            canvas { i, _ in levels.indices.contains(i) ? levels[i] : 0 }
        }
    }

    private func canvas(_ level: @escaping (Int, Int) -> Double) -> some View {
        let n = forming == nil ? levels.count : columns
        return Canvas { context, size in
            guard n > 0 else { return }
            let pitch = size.width / Double(n)
            let d = pitch * 0.62
            let rows = max(1, Int(size.height / 2 / pitch))
            for i in 0..<n {
                let k = max(1, Int((level(i, n) * Double(rows)).rounded()))
                let color = forming == nil && i < played ? lit : dot
                let x = Double(i) * pitch + (pitch - d) / 2
                for r in 0..<k {
                    let up = CGRect(x: x, y: size.height / 2 - Double(r + 1) * pitch + (pitch - d) / 2, width: d, height: d)
                    let down = CGRect(x: x, y: size.height / 2 + Double(r) * pitch + (pitch - d) / 2, width: d, height: d)
                    context.fill(Path(up), with: .color(color))
                    context.fill(Path(down), with: .color(color))
                }
            }
        }
    }
}

/// The hero's wave: a click seeks, a drag scrubs and seeks where it ends.
struct SeekableWave: View {
    let wave: PlayerCard.Wave
    let seek: (Double) -> Void
    var height: Double = 92
    @State private var scrub: Double?

    var body: some View {
        GeometryReader { geo in
            let played = scrub.map { Int(($0 * Double(Decide.waveBars)).rounded(.down)) } ?? wave.played
            DotWave(levels: wave.levels, played: played, dot: .primary.opacity(0.3), lit: .primary)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { scrub = Self.fraction($0.location.x, geo.size.width) }
                        .onEnded {
                            seek(Self.fraction($0.location.x, geo.size.width))
                            scrub = nil
                        }
                )
        }
        .frame(height: height)
        .helped(Control(help: wave.help))
        .accessibilityAddTraits(.isButton)
    }

    static func fraction(_ x: Double, _ width: Double) -> Double {
        width > 0 ? min(1, max(0, x / width)) : 0
    }
}
