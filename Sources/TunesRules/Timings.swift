import TunesContract

/// One model's stage timings, the last five of each.
public struct StageTimings: Equatable, Sendable {
    public var writing: [Double]
    public var rendering: [Double]

    public init(writing: [Double] = [], rendering: [Double] = []) {
        self.writing = writing
        self.rendering = rendering
    }
}

/// Stage timings per model, the chosen model, the modes and the player's
/// level, as the state file keeps them.
public struct SavedState: Equatable, Sendable {
    /// By model id.
    public var timings: [String: StageTimings]
    /// The chosen model's id; nil until one is chosen.
    public var model: String?
    public var shuffle: Bool
    public var `repeat`: RepeatMode
    /// The player's level, 0 to 1.
    public var volume: Double

    /// The model whose timings a state file from before the choice keeps
    /// at its top level: the only one there was.
    public static let firstModel = "large"

    public init(
        timings: [String: StageTimings] = [:], model: String? = nil, shuffle: Bool = true, repeat: RepeatMode = .all,
        volume: Double = 1
    ) {
        self.timings = timings
        self.model = model
        self.shuffle = shuffle
        self.repeat = `repeat`
        self.volume = volume
    }

    /// The state file's text read back; anything missing or malformed reads
    /// as its default: no timings, no model, shuffle on, repeat all, volume
    /// 1. A volume outside 0…1 is malformed. Without `timings`, the
    /// `writing` and `rendering` arrays are `firstModel`'s.
    public static func parse(_ text: String?) -> SavedState {
        guard let text, case .object(let fields)? = try? JSONValue.parse(text) else { return SavedState() }
        func value(_ key: String) -> JSONValue? { fields.first(where: { $0.key == key })?.value }
        func timings(_ v: JSONValue?) -> [Double] {
            guard case .array(let values)? = v else { return [] }
            var out: [Double] = []
            for v in values {
                guard let d = v.number, d.isFinite, d >= 0 else { return [] }
                out.append(d)
            }
            return Array(out.suffix(Rules.timingsKept))
        }
        func stages(_ v: JSONValue?) -> StageTimings? {
            let t = StageTimings(writing: timings(v?["writing"]), rendering: timings(v?["rendering"]))
            return t.writing.isEmpty && t.rendering.isEmpty ? nil : t
        }
        var state = SavedState()
        if case .object(let models)? = value("timings") {
            for (id, v) in models where !id.isEmpty {
                if let t = stages(v) { state.timings[id] = t }
            }
        } else if let t = stages(.object(fields)) {
            state.timings[firstModel] = t
        }
        if case .string(let m)? = value("model"), !m.isEmpty { state.model = m }
        if case .bool(let b)? = value("shuffle") { state.shuffle = b }
        if case .string(let s)? = value("repeat"), let mode = RepeatMode(rawValue: s) { state.repeat = mode }
        if let v = value("volume")?.number, (0...1).contains(v) { state.volume = v }
        return state
    }

    /// The state file's text.
    public var text: String {
        var out: [(key: String, value: JSONValue)] = []
        if let model { out.append(("model", .string(model))) }
        out.append(("timings", .object(timings.sorted { $0.key < $1.key }.map { id, t in
            (id, .object([("writing", .array(t.writing.map { .double($0) })), ("rendering", .array(t.rendering.map { .double($0) }))]))
        })))
        out += [
            ("shuffle", .bool(shuffle)),
            ("repeat", .string(self.repeat.rawValue)),
            ("volume", .double(volume)),
        ]
        return JSONValue.object(out).dumps() + "\n"
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
