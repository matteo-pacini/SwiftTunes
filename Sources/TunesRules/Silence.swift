/// What a plan's audio codes say about silence.
public struct PlanVerdict: Equatable, Sendable {
    /// Seconds where a final silent run of at least `Rules.tailMin` starts.
    public var cut: Double?
    /// The longest other silent run over `Rules.midMax`, in seconds: the plan
    /// is written again.
    public var rewrite: Double?

    public init(cut: Double?, rewrite: Double?) {
        self.cut = cut
        self.rewrite = rewrite
    }
}

public enum Silence {
    public struct NoCodes: Error, Equatable, CustomStringConvertible {
        public init() {}
        public var description: String { "no audio codes" }
    }

    /// The plan's audio codes, written as "1,2,3," by the language model.
    public static func parseCodes(_ text: String?) throws(NoCodes) -> [Int] {
        guard let text else { throw NoCodes() }
        var codes: [Int] = []
        for piece in text.split(separator: ",", omittingEmptySubsequences: false) {
            let t = piece.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            guard let n = Int(t) else { throw NoCodes() }
            codes.append(n)
        }
        if codes.isEmpty { throw NoCodes() }
        return codes
    }

    /// (start index, length) of every run of `silence`.
    public static func runs(_ codes: [Int], silence: Int) -> [(start: Int, length: Int)] {
        var out: [(start: Int, length: Int)] = []
        var start: Int?
        for (i, c) in codes.enumerated() {
            if c == silence {
                if start == nil { start = i }
            } else if let s = start {
                out.append((s, i - s))
                start = nil
            }
        }
        if let s = start { out.append((s, codes.count - s)) }
        return out
    }

    public static func verdict(_ codes: [Int], silence: Int, hz: Double = Rules.codeHz) -> PlanVerdict {
        var cut: Double?
        var worst = 0.0
        for run in runs(codes, silence: silence) {
            let seconds = Double(run.length) / hz
            if run.start + run.length == codes.count && seconds >= Rules.tailMin {
                cut = Double(run.start) / hz
            } else if seconds > Rules.midMax {
                worst = max(worst, seconds)
            }
        }
        return PlanVerdict(cut: cut, rewrite: worst > 0 ? worst : nil)
    }
}
