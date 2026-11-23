import TunesContract

/// The command each player control not aimed at a tune sends; nil when the
/// control has nothing to act on. Commands aimed at a tune are built with
/// the card, from the tune as drawn (`PlayerCard.Now.scrapCommand`, the rows'
/// commands).
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

    public static func composer(_ s: Snapshot) -> Command { .setComposer(on: !s.composing) }

    public static func retry(_ s: Snapshot) -> Command? {
        s.composing && (s.model.state == .failed || s.model.state == .noDevice) ? .retry : nil
    }

    public static func undo(_ s: Snapshot, now: Double) -> Command? {
        Decide.undoActive(s, now: now) ? .undo : nil
    }
}
