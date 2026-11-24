import TunesContract

/// A tune's place in the round.
public enum RoundState: Sendable, Equatable {
    case played, playing, waiting
}

/// One tune of the round, in list order.
public struct RoundEntry: Sendable, Equatable {
    /// Its place in the round, from 1.
    public var number: Int
    public var state: RoundState
    /// Its index in `played` or `queue`; 0 for the playing tune.
    public var index: Int
    /// Stable while the same tune keeps its place in the list, even when a
    /// tune is put back before it: the file and how many times the same
    /// file came earlier in the list.
    public var id: String
    public var name: String
    public var file: String
    public var bpm: Int?
    public var key: String?
    public var length: Double?
    public var new: Bool
    public var pinned: Bool
    public var sung: Bool
}

extension Decide {
    /// The round as one list: the tunes played this round, oldest first, the
    /// playing tune, then the queue, numbered from 1 in that order.
    public static func round(played: [QueuedTune], tune: PlayingTune?, queue: [QueuedTune]) -> [RoundEntry] {
        var entries: [RoundEntry] = []
        var seen: [String: Int] = [:]
        func add(_ state: RoundState, _ index: Int, name: String, file: String, bpm: Int?, key: String?, length: Double?, new: Bool, pinned: Bool, sung: Bool) {
            let k = seen[file, default: 0]
            seen[file] = k + 1
            entries.append(RoundEntry(number: entries.count + 1, state: state, index: index, id: "\(file)#\(k)", name: name, file: file,
                                      bpm: bpm, key: key, length: length, new: new, pinned: pinned, sung: sung))
        }
        for (i, q) in played.enumerated() {
            add(.played, i, name: q.name, file: q.file, bpm: q.bpm, key: q.key, length: q.length, new: q.new, pinned: q.pinned, sung: q.sung)
        }
        if let t = tune {
            add(.playing, 0, name: t.name, file: t.file, bpm: t.bpm, key: t.key, length: t.length, new: t.new, pinned: t.pinned, sung: t.sung)
        }
        for (i, q) in queue.enumerated() {
            add(.waiting, i, name: q.name, file: q.file, bpm: q.bpm, key: q.key, length: q.length, new: q.new, pinned: q.pinned, sung: q.sung)
        }
        return entries
    }

    /// The player list's right-hand text: `N of M` while a tune plays, else
    /// `M tunes`, or `nothing` for an empty round.
    public static func roundCount(_ round: [RoundEntry]) -> String {
        if let playing = round.first(where: { $0.state == .playing }) { return "\(playing.number) of \(round.count)" }
        return round.isEmpty ? "nothing" : Format.plural(round.count, "tune", "tunes")
    }

    /// Rows the player's list shows at once.
    public static let listRows = 4

    /// How long after the user scrolls the list it is left alone.
    public static let handsOffSeconds = 3.0

    /// Where the list goes when the playing tune changes or the popover
    /// opens: the index of the row to bring to the top, so the playing row is
    /// second from the top while the round is long enough; nil to leave the
    /// list where it is. It is left alone with nothing playing, when the
    /// whole round fits, while the pointer is over it, and within
    /// `handsOffSeconds` of the user scrolling it.
    public static func listTop(count: Int, playing: Int?, pointerInside: Bool, userScrolledAt: Double?, now: Double) -> Int? {
        guard let playing, count > listRows, !pointerInside else { return nil }
        if let at = userScrolledAt, now - at < handsOffSeconds { return nil }
        return max(0, min(playing - 1, count - listRows))
    }
}

extension PlayerCard.Row {
    /// How opaque the row's content is drawn: a dim row's text, picture and
    /// number at 0.45, back to full while the pointer is over it, so its
    /// actions read clearly.
    public func contentOpacity(hovered: Bool) -> Double {
        dim && !hovered ? 0.45 : 1
    }
}
