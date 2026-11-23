/// The model download's arithmetic and wording.
public enum DownloadRules {
    /// Where a file's download resumes: the part's size, or 0 when there is
    /// none or it is bigger than the file (the part is then thrown away).
    public static func resumeOffset(partBytes: Int64?, expected: Int64) -> Int64 {
        guard let partBytes, partBytes <= expected else { return 0 }
        return partBytes
    }

    /// The Range header for a resume, nil from the start.
    public static func rangeHeader(offset: Int64) -> String? {
        offset > 0 ? "bytes=\(offset)-" : nil
    }

    /// Whether a reply honours the range asked for; any other status means
    /// the file is fetched again from the start.
    public static func resumes(offset: Int64, status: Int) -> Bool {
        offset > 0 && status == 206
    }

    public static func httpError(file: String, status: Int) -> String { "\(file): HTTP \(status)" }
    public static func reasonError(file: String, reason: String) -> String { "\(file): \(reason)" }
    public static func brokeError(file: String, kind: String) -> String { "\(file): the connection broke (\(kind))" }
    public static func shortError(file: String, got: Int64, expected: Int64) -> String { "\(file): got \(got) of \(expected) bytes" }
    public static func checksumError(file: String) -> String { "\(file): checksum mismatch" }
}

/// Bytes a second over the last two seconds of blocks.
public struct RateWindow: Sendable {
    private var blocks: [(at: Double, bytes: Int64)] = []

    public init() {}

    /// Adds a block received at `now` and returns the rate: the bytes of the
    /// last two seconds over their span, the span at least half a second.
    public mutating func add(_ bytes: Int64, at now: Double) -> Double {
        blocks.append((now, bytes))
        blocks.removeAll { $0.at < now - 2 }
        let span = max(now - (blocks.first?.at ?? now), 0.5)
        return Double(blocks.reduce(0) { $0 + $1.bytes }) / span
    }
}
