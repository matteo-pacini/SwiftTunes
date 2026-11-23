import TunesContract

/// The order a round plays its kept tunes in. Tunes are file names; they
/// sort in the order made because they begin with when the tune was made.
public enum Rounds {
    /// The order made, going round from `anchor`: those made after it, then
    /// those made before it or it.
    public static func made(_ tunes: [String], after anchor: String?) -> [String] {
        let sorted = tunes.sorted()
        guard let anchor else { return sorted }
        return sorted.filter { $0 > anchor } + sorted.filter { $0 <= anchor }
    }

    /// A round's order over `tunes`, drawn once: shuffled with shuffle on,
    /// else the order made going round from `anchor`. It never starts with
    /// `avoid` (the tune that ended the last round) when there is another.
    public static func draw<R: RandomNumberGenerator>(
        _ tunes: [String], shuffle: Bool, anchor: String?, avoid: String?, rng: inout R
    ) -> [String] {
        var order = shuffle ? tunes.shuffled(using: &rng) : made(tunes, after: anchor)
        if let avoid, order.count > 1, order.first == avoid {
            let other = shuffle ? Int.random(in: 1..<order.count, using: &rng) : 1
            order.swapAt(0, other)
        }
        return order
    }

    /// The order with tunes that are gone dropped, and kept tunes it lacks
    /// (not in `excluded`: played this round, playing, queued) added at the
    /// end in the order made.
    public static func reconciled(_ order: [String], kept: [String], excluded: Set<String>) -> [String] {
        let present = Set(kept)
        let staying = order.filter(present.contains)
        return staying + present.subtracting(staying).subtracting(excluded).sorted()
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
