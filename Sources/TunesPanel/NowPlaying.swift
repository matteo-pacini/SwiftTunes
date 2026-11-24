import TunesContract

/// What the system's Now Playing shows, from the snapshot.
public struct NowPlaying: Sendable, Equatable {
    public enum State: Sendable, Equatable { case playing, paused, stopped }
    public var state: State
    /// nil when nothing is loaded.
    public var title: String?
    public var genre: String?
    public var duration: Double?
    public var elapsed: Double
    /// 1 while playing, else 0.
    public var rate: Double
    /// Which remote commands act now.
    public var canNext: Bool
    public var canPrevious: Bool
    public var canSeek: Bool

    public static func of(_ s: Snapshot, now: Double) -> NowPlaying {
        guard let t = s.tune, s.player != .none else {
            return NowPlaying(state: .stopped, title: nil, genre: nil, duration: nil, elapsed: 0, rate: 0, canNext: false, canPrevious: false, canSeek: false)
        }
        let playing = s.player == .playing
        return NowPlaying(
            state: playing ? .playing : .paused,
            title: t.name,
            genre: Decide.genreName(s),
            duration: t.length,
            elapsed: Decide.position(s, now: now),
            rate: playing ? 1 : 0,
            canNext: s.canNext,
            canPrevious: true,
            canSeek: (t.length ?? 0) > 0
        )
    }
}
