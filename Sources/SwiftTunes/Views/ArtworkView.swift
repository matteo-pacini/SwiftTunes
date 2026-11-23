import SwiftUI
import TunesContract
import TunesPanel

/// A tune's picture: its mesh in the genre's field colours and its small
/// dot wave. With a stage instead, the job's forming wave over a dimmer
/// field.
struct ArtworkView: View {
    var artwork: Artwork?
    var palette: Palette
    var stage: JobStage?
    var corner: Double = 9

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let field = palette.field(dark: scheme == .dark)
        ZStack {
            if let artwork {
                MeshGradient(width: 3, height: 3, points: artwork.points.map { SIMD2(Float($0.x), Float($0.y)) }, colors: artwork.colors(field).map(\.color))
                DotWave(levels: artwork.levels, dot: .white.opacity(0.8), lit: .white)
                    .padding(.horizontal, 4)
            } else {
                MeshGradient(width: 3, height: 3, points: Backdrop.points(at: 0), colors: Backdrop.colors(field.map(\.color)))
                    .opacity(0.55)
                if let stage {
                    DotWave(levels: [], forming: stage, columns: Artwork.columns, dot: .white.opacity(0.8), lit: .white)
                        .padding(.horizontal, 4)
                }
            }
        }
        .clipShape(.rect(cornerRadius: corner))
    }
}
