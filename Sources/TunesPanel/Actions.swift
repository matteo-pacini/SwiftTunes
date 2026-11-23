import TunesContract

/// The command each player control sends, carrying the tune's name where it
/// aims at a tune; nil when the control has nothing to act on.
public enum Actions {
    public static func playPause(_ s: Snapshot) -> Command? {
        Decide.nowSection(s, now: 0).playPause.enabled ? .toggle : nil
    }

    public static func next(_ s: Snapshot) -> Command? { s.canNext ? .next : nil }

    public static func shuffle(_ s: Snapshot) -> Command { .setShuffle(on: !s.shuffle) }

    /// all → one → off → all.
    public static func `repeat`(_ s: Snapshot) -> Command {
        switch s.repeat {
        case .all: .setRepeat(.one)
        case .one: .setRepeat(.off)
        case .off: .setRepeat(.all)
        }
    }

    public static func scrapPlaying(_ s: Snapshot) -> Command? {
        s.tune.map { .scrapPlaying(name: $0.name) }
    }

    public static func scrapQueued(_ s: Snapshot, index: Int) -> Command? {
        s.queue.indices.contains(index) ? .scrapQueued(index: index, name: s.queue[index].name) : nil
    }

    public static func playQueued(_ s: Snapshot, index: Int) -> Command? {
        s.queue.indices.contains(index) ? .playQueued(index: index, name: s.queue[index].name) : nil
    }

    public static func scrapJob(_ s: Snapshot) -> Command? {
        Decide.jobShown(s) ? .scrapJob : nil
    }

    public static func composer(_ s: Snapshot) -> Command { .setComposer(on: !s.composing) }

    public static func retry(_ s: Snapshot) -> Command? {
        s.composing && (s.model.state == .failed || s.model.state == .noDevice) ? .retry : nil
    }

    public static func undo(_ s: Snapshot, now: Double) -> Command? {
        Decide.undoActive(s, now: now) ? .undo : nil
    }
}
