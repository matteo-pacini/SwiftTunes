import TunesContract

/// Which kept tune plays next. Tunes are file names; they sort in the order
/// made because they begin with when the tune was made.
public enum Rounds {
    /// The kept tunes this round has still to play: not played this round
    /// and not busy (playing or queued). Oldest first; with shuffle off,
    /// those made after `anchor` (the last kept tune started) come first,
    /// then those before it, so the order goes round and skips none.
    public static func left(kept: [String], played: Set<String>, shuffle: Bool, anchor: String?, busy: Set<String> = []) -> [String] {
        let left = kept.sorted().filter { !played.contains($0) && !busy.contains($0) }
        guard !shuffle, let anchor else { return left }
        return left.filter { $0 > anchor } + left.filter { $0 <= anchor }
    }

    /// The next kept tune, or nil, and whether it starts a new round. At
    /// random with shuffle on, else the first of the round; a round over
    /// starts another unless repeat is off.
    public static func choose<R: RandomNumberGenerator>(
        kept: [String], played: Set<String>, busy: Set<String>, shuffle: Bool, anchor: String?,
        repeat mode: RepeatMode, rng: inout R
    ) -> (tune: String?, wraps: Bool) {
        var remaining = left(kept: kept, played: played, shuffle: shuffle, anchor: anchor, busy: busy)
        var wraps = false
        if remaining.isEmpty && mode != .off {
            remaining = left(kept: kept, played: [], shuffle: shuffle, anchor: nil, busy: busy)
            wraps = true
        }
        guard !remaining.isEmpty else { return (nil, false) }
        return (shuffle ? remaining.randomElement(using: &rng) : remaining.first, wraps)
    }

    /// With shuffle off, up to `count` kept tunes that play after `first`
    /// (the next kept tune, which starts a new round when `wraps`), in order.
    public static func after(
        kept: [String], played: Set<String>, busy: Set<String>, anchor: String?, repeat mode: RepeatMode,
        first: String, wraps: Bool, count: Int
    ) -> [String] {
        var played = wraps ? [first] : played.union([first])
        var anchor = first
        var out: [String] = []
        var unused = SplitMix64(seed: 0)
        while out.count < count {
            let (next, wrap) = choose(kept: kept, played: played, busy: busy, shuffle: false, anchor: anchor, repeat: mode, rng: &unused)
            guard let next, next != first, !out.contains(next) else { break }
            played = wrap ? [next] : played.union([next])
            anchor = next
            out.append(next)
        }
        return out
    }
}

/// What goes into a tune's requests.
public enum Composing {
    /// The genre's caption, two distinct turns at random (fewer if it has
    /// fewer), then "instrumental", joined by ", ".
    public static func caption<R: RandomNumberGenerator>(caption: String, turns: [String], rng: inout R) -> String {
        let distinct = Array(Set(turns)).sorted()
        let picked = Array(distinct.shuffled(using: &rng).prefix(2))
        return ([caption] + picked + ["instrumental"]).joined(separator: ", ")
    }

    /// A tempo in the genre's range, both ends included.
    public static func bpm<R: RandomNumberGenerator>(_ range: [Int], rng: inout R) -> Int {
        Int.random(in: range[0]...range[1], using: &rng)
    }

    /// "<mood> <thing>".
    public static func name<R: RandomNumberGenerator>(moods: [String], things: [String], rng: inout R) -> String {
        "\(moods.randomElement(using: &rng) ?? "Quiet") \(things.randomElement(using: &rng) ?? "Tune")"
    }
}

/// A seeded generator for tests and anything that must repeat.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
