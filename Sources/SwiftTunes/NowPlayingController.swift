import MediaPlayer
import TunesContract
import TunesPanel

/// Fills the system's Now Playing from each snapshot and turns the remote
/// commands into contract commands.
final class NowPlayingController {
    private let model: PanelModel
    private let center = MPRemoteCommandCenter.shared()

    init(model: PanelModel) {
        self.model = model
        let send: @MainActor @Sendable (Command) -> Void = { [weak model] in model?.send($0) }
        center.playCommand.addTarget(handler: Self.handler { _ in send(.play) })
        center.pauseCommand.addTarget(handler: Self.handler { _ in send(.pause) })
        center.togglePlayPauseCommand.addTarget(handler: Self.handler { _ in send(.toggle) })
        center.nextTrackCommand.addTarget(handler: Self.handler { _ in send(.next) })
        center.stopCommand.addTarget(handler: Self.handler { _ in send(.stop) })
        center.changePlaybackPositionCommand.addTarget(handler: Self.handler { position in
            if let position { send(.seek(to: position)) }
        })
        center.previousTrackCommand.isEnabled = false
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
        info.nowPlayingInfo = d
        info.playbackState = n.state == .playing ? .playing : .paused
    }
}
