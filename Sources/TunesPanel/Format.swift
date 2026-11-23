import Foundation

/// Number and time formats shared by every card.
public enum Format {
    static let gibBytes = 1_073_741_824.0

    /// "1:24", "12:05"; "–:––" for none or a negative time.
    public static func clock(_ seconds: Double?) -> String {
        guard let s = seconds, s.isFinite, s >= 0 else { return "–:––" }
        let whole = Int(s.rounded(.down))
        let r = whole % 60
        return "\(whole / 60):\(r < 10 ? "0" : "")\(r)"
    }

    /// "19.3 GiB", "8 GiB" (a whole number loses its ".0"), "226 GiB" from
    /// 100 up.
    public static func gib(_ bytes: Int64, decimals: Int = 1) -> String {
        "\(gibNumber(bytes, decimals: decimals)) GiB"
    }

    /// The number part of `gib`.
    public static func gibNumber(_ bytes: Int64, decimals: Int = 1) -> String {
        let g = Double(bytes) / gibBytes
        return trimmed(g, decimals: g >= 100 ? 0 : decimals)
    }

    /// "28 MB/s", "640 kB/s".
    public static func rate(_ bytesPerSecond: Double) -> String {
        bytesPerSecond >= 1e6
            ? "\(Int((bytesPerSecond / 1e6).rounded())) MB/s"
            : "\(Int((bytesPerSecond / 1e3).rounded())) kB/s"
    }

    /// "4.1 MB" from 1e6 bytes up, else "820 kB", at least "1 kB".
    public static func size(_ bytes: Int64) -> String {
        let b = Double(bytes)
        if b >= 1e6 { return String(format: "%.1f MB", b / 1e6) }
        return "\(max(1, Int((b / 1e3).rounded()))) kB"
    }

    /// `path` with the home folder shown as `~`.
    public static func tilde(_ path: String, home: String) -> String {
        var h = home
        while h.count > 1 && h.hasSuffix("/") { h.removeLast() }
        guard !h.isEmpty else { return path }
        if path == h { return "~" }
        if path.hasPrefix(h + "/") { return "~" + path.dropFirst(h.count) }
        return path
    }

    /// A count with a comma every three digits: "2,000".
    public static func grouped(_ n: Int) -> String {
        let digits = Array(String(abs(n)))
        var out = n < 0 ? "-" : ""
        for (i, d) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(d)
        }
        return out
    }

    /// "1 kept tune", "14 kept tunes".
    static func plural(_ n: Int, _ one: String, _ many: String) -> String {
        "\(n) \(n == 1 ? one : many)"
    }

    /// Outside text as a sentence: a full stop added unless it ends in one.
    static func sentence(_ text: String) -> String {
        guard let last = text.last, ".!?…".contains(last) else { return text + "." }
        return text
    }

    private static func trimmed(_ value: Double, decimals: Int) -> String {
        var s = String(format: "%.\(decimals)f", value)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s
    }
}
