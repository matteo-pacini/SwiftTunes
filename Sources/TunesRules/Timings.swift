import TunesContract

/// Stage timings, the modes and the player's level, as the state file keeps them.
public struct SavedState: Equatable, Sendable {
    public var writing: [Double]
    public var rendering: [Double]
    public var shuffle: Bool
    public var `repeat`: RepeatMode
    /// The player's level, 0 to 1.
    public var volume: Double

    public init(writing: [Double] = [], rendering: [Double] = [], shuffle: Bool = true, repeat: RepeatMode = .all, volume: Double = 1) {
        self.writing = writing
        self.rendering = rendering
        self.shuffle = shuffle
        self.repeat = `repeat`
        self.volume = volume
    }

    /// The state file's text read back; anything missing or malformed reads
    /// as its default: no timings, shuffle on, repeat all, volume 1. A volume
    /// outside 0…1 is malformed.
    public static func parse(_ text: String?) -> SavedState {
        guard let text, case .object(let fields)? = try? JSONValue.parse(text) else { return SavedState() }
        func value(_ key: String) -> JSONValue? { fields.first(where: { $0.key == key })?.value }
        func timings(_ key: String) -> [Double] {
            guard case .array(let values)? = value(key) else { return [] }
            var out: [Double] = []
            for v in values {
                guard let d = v.number, d.isFinite, d >= 0 else { return [] }
                out.append(d)
            }
            return Array(out.suffix(Rules.timingsKept))
        }
        var state = SavedState(writing: timings("writing"), rendering: timings("rendering"))
        if case .bool(let b)? = value("shuffle") { state.shuffle = b }
        if case .string(let s)? = value("repeat"), let mode = RepeatMode(rawValue: s) { state.repeat = mode }
        if let v = value("volume")?.number, (0...1).contains(v) { state.volume = v }
        return state
    }

    /// The state file's text.
    public var text: String {
        JSONValue.object([
            ("writing", .array(writing.map { .double($0) })),
            ("rendering", .array(rendering.map { .double($0) })),
            ("shuffle", .bool(shuffle)),
            ("repeat", .string(self.repeat.rawValue)),
            ("volume", .double(volume)),
        ]).dumps() + "\n"
    }
}

public enum Timings {
    /// The median, nil for none; an even count gives the mean of the middle two.
    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        let mid = s.count / 2
        return s.count % 2 == 1 ? s[mid] : (s[mid - 1] + s[mid]) / 2
    }

    /// `values` with `seconds` (to a tenth) appended, the last five only.
    public static func adding(_ seconds: Double, to values: [Double]) -> [Double] {
        Array((values + [tenth(seconds)]).suffix(Rules.timingsKept))
    }

    /// Both medians, or nil until each stage has been timed once.
    public static func expect(writing: [Double], rendering: [Double]) -> Expect? {
        guard let w = median(writing), let r = median(rendering) else { return nil }
        return Expect(writingS: w, renderingS: r)
    }

    public static func tenth(_ x: Double) -> Double {
        (x * 10).rounded(.toNearestOrEven) / 10
    }
}
