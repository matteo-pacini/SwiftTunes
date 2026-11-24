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
    /// new tune is inserted before it: the file and how many times the same
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

    /// The entries the player shows, always consecutive: the playing tune
    /// and the next two, reaching back over played tunes when fewer than two
    /// follow it, so the window keeps three rows while the round has them;
    /// with nothing playing, the next three. And how many follow the window.
    public static func roundWindow(_ round: [RoundEntry]) -> (rows: ArraySlice<RoundEntry>, more: Int) {
        let start: Int
        if let playing = round.firstIndex(where: { $0.state == .playing }) {
            start = max(0, min(playing, round.endIndex - upNextRows))
        } else {
            start = round.firstIndex { $0.state != .played } ?? round.endIndex
        }
        let rows = round[start..<min(round.endIndex, start + upNextRows)]
        return (rows, round.endIndex - rows.endIndex)
    }

    /// The player list's right-hand text: `N of M` while a tune plays, else
    /// `M tunes`, or `nothing` for an empty round.
    public static func roundCount(_ round: [RoundEntry]) -> String {
        if let playing = round.first(where: { $0.state == .playing }) { return "\(playing.number) of \(round.count)" }
        return round.isEmpty ? "nothing" : Format.plural(round.count, "tune", "tunes")
    }

    /// The round card's right-hand text: the order, then the repeat mode.
    public static func roundModes(shuffle: Bool, repeat mode: RepeatMode) -> String {
        let order = shuffle ? "shuffled" : "in the order made"
        let again = switch mode {
        case .all: "repeat all"
        case .one: "repeat one"
        case .off: "repeat off"
        }
        return "\(order) · \(again)"
    }

    /// The row the round card brings into view: the playing tune's, nil
    /// when nothing plays.
    public static func roundScrollTarget(_ rows: [PlayerCard.Row]) -> String? {
        rows.first { $0.state == .playing }?.id
    }
}
