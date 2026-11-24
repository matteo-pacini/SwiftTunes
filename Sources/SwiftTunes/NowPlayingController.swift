import MediaPlayer
import SwiftUI
import TunesContract
import TunesPanel

/// Fills the system's Now Playing from each snapshot and turns the remote
/// commands into contract commands.
final class NowPlayingController {
    private let model: PanelModel
    private let center = MPRemoteCommandCenter.shared()
    /// The last tune's picture and what it was drawn for, so each tune is
    /// drawn once.
    private var artwork: (key: String, item: MPMediaItemArtwork)?

    init(model: PanelModel) {
        self.model = model
        let send: @MainActor @Sendable (Command) -> Void = { [weak model] in model?.send($0) }
        center.playCommand.addTarget(handler: Self.handler { _ in send(.play) })
        center.pauseCommand.addTarget(handler: Self.handler { _ in send(.pause) })
        center.togglePlayPauseCommand.addTarget(handler: Self.handler { _ in send(.toggle) })
        center.nextTrackCommand.addTarget(handler: Self.handler { _ in send(.next) })
        center.previousTrackCommand.addTarget(handler: Self.handler { _ in send(.previous) })
        center.stopCommand.addTarget(handler: Self.handler { _ in send(.stop) })
        center.changePlaybackPositionCommand.addTarget(handler: Self.handler { position in
            if let position { send(.seek(to: position)) }
        })
    }

    /// A remote command handler that reads what it needs from the event,
    /// then hops to the main actor: MediaPlayer does not promise which
    /// thread calls it.
    private nonisolated static func handler(
        _ act: @escaping @MainActor @Sendable (Double?) -> Void
    ) -> (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        { event in
            let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime
            Task { @MainActor in act(position) }
            return .success
        }
    }

    func update(_ s: Snapshot) {
        let n = NowPlaying.of(s, now: PanelModel.clock())
        let info = MPNowPlayingInfoCenter.default()
        center.nextTrackCommand.isEnabled = n.canNext
        center.previousTrackCommand.isEnabled = n.canPrevious
        center.changePlaybackPositionCommand.isEnabled = n.canSeek
        guard let title = n.title else {
            info.nowPlayingInfo = nil
            info.playbackState = .stopped
            return
        }
        var d: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: n.elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: n.rate,
        ]
        if let genre = n.genre {
            d[MPMediaItemPropertyGenre] = genre
            d[MPMediaItemPropertyArtist] = genre
        }
        if let duration = n.duration { d[MPMediaItemPropertyPlaybackDuration] = duration }
        if let item = picture(for: s) { d[MPMediaItemPropertyArtwork] = item }
        info.nowPlayingInfo = d
        info.playbackState = n.state == .playing ? .playing : .paused
    }

    /// The tune's artwork for the widget, drawn the first time a tune (by its
    /// file and the name it is drawn from) is seen.
    private func picture(for s: Snapshot) -> MPMediaItemArtwork? {
        guard let t = s.tune else { return nil }
        let key = "\(t.file)|\(t.name)"
        if let artwork, artwork.key == key { return artwork.item }
        let recipe = Artwork.recipe(name: t.name, bpm: t.bpm, key: t.key, palette: Decide.palette(s))
        let renderer = ImageRenderer(content: ArtworkView(artwork: recipe, palette: Decide.palette(s), corner: 0)
            .frame(width: 300, height: 300)
            .environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let image = renderer.cgImage else { return nil }
        let item = MPMediaItemArtwork(boundsSize: CGSize(width: 300, height: 300), requestHandler: Self.handler(image))
        artwork = (key, item)
        return item
    }

    /// MediaPlayer asks for the picture on a queue of its own, so the
    /// handler must not belong to the main actor; it holds only an
    /// immutable image.
    private nonisolated static func handler(_ image: CGImage) -> @Sendable (CGSize) -> NSImage {
        { _ in NSImage(cgImage: image, size: CGSize(width: 300, height: 300)) }
    }
}
