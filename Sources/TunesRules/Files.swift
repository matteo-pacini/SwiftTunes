import Foundation

/// Tune files: their names, the keep rule, pins and exported copies.
public enum TuneFiles {
    /// The key's words joined by dashes: letters, digits and "#" only;
    /// "unknown" when none.
    public static func keyPart(_ key: String?) -> String {
        var words: [String] = []
        var word = ""
        for u in (key ?? "").unicodeScalars {
            if isKeyScalar(u) {
                word.unicodeScalars.append(u)
            } else if !word.isEmpty {
                words.append(word)
                word = ""
            }
        }
        if !word.isEmpty { words.append(word) }
        return words.isEmpty ? "unknown" : words.joined(separator: "-")
    }

    /// `<YYYYMMDD-HHMMSS>-<bpm>bpm-<key>.m4a`, the time read in `timeZone`.
    public static func fileName(at when: Date, timeZone: TimeZone, bpm: Int, key: String?) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: when)
        func two(_ n: Int?) -> String { n.map { $0 < 10 ? "0\($0)" : "\($0)" } ?? "00" }
        let stamp = "\(c.year ?? 0)" + two(c.month) + two(c.day) + "-" + two(c.hour) + two(c.minute) + two(c.second)
        return "\(stamp)-\(bpm)bpm-\(keyPart(key)).\(Rules.tuneExtension)"
    }

    /// (bpm, key with spaces) for a file named as a tune, nil for any other.
    public static func parse(_ name: String) -> (bpm: Int, key: String)? {
        let ext = "." + Rules.tuneExtension
        guard name.hasSuffix(ext) else { return nil }
        let u = Array(name.unicodeScalars.dropLast(ext.unicodeScalars.count))
        func digits(_ range: Range<Int>) -> Bool {
            range.upperBound <= u.count && range.allSatisfy { ("0"..."9").contains(u[$0]) }
        }
        guard digits(0..<8), u.count > 8, u[8] == "-", digits(9..<15), u.count > 15, u[15] == "-" else { return nil }
        var i = 16
        while i < u.count, ("0"..."9").contains(u[i]) { i += 1 }
        let bpmDigits = i - 16
        guard (1...3).contains(bpmDigits) else { return nil }
        let rest = Array(u[i...])
        let tag: [Unicode.Scalar] = ["b", "p", "m", "-"]
        guard rest.count > 4, Array(rest[0..<4]) == tag else { return nil }
        let key = Array(rest[4...])
        guard key.first != "-", key.last != "-" else { return nil }
        var previousDash = false
        for s in key {
            if s == "-" {
                if previousDash { return nil }
                previousDash = true
            } else {
                guard isKeyScalar(s) else { return nil }
                previousDash = false
            }
        }
        let bpm = Int(String(String.UnicodeScalarView(u[16..<i])))!
        return (bpm, String(String.UnicodeScalarView(key)).replacingOccurrences(of: "-", with: " "))
    }

    public static func isTune(_ name: String) -> Bool { parse(name) != nil }

    /// A tune's name without its extension.
    public static func stem(_ name: String) -> String {
        let ext = "." + Rules.tuneExtension
        return name.hasSuffix(ext) ? String(name.dropLast(ext.count)) : name
    }

    /// Our tunes to delete, oldest first, so that `keep` remain. Files not
    /// named as tunes and pinned ones are never counted or returned;
    /// protected ones (playing, queued, just made) are counted, never returned.
    public static func keepVictims(_ names: [String], keep: Int, protected: Set<String>, pinned: Set<String> = []) -> [String] {
        let ours = names.filter { isTune($0) && !pinned.contains($0) }.sorted()
        var excess = ours.count - keep
        var out: [String] = []
        for n in ours where excess > 0 {
            if protected.contains(n) { continue }
            out.append(n)
            excess -= 1
        }
        return out
    }

    /// The hidden empty file beside a tune that keeps it for good.
    public static func pinMark(_ name: String) -> String { ".\(name).pin" }

    /// The hidden file a tune is written to before it takes its name.
    public static func partName(_ name: String) -> String { ".\(name).part" }

    /// A free name `<genre> - <title>.m4a` (" (2)", " (3)"… while taken),
    /// usable as one path component.
    public static func exportName(genre: String, title: String, taken: Set<String>) -> String {
        var base = String(String.UnicodeScalarView("\(genre) - \(title)".unicodeScalars.filter { !isControl($0) }))
        base = base.replacingOccurrences(of: "/", with: "-")
        base = base.trimmingCharacters(in: .whitespacesAndNewlines)
        base = String(base.drop(while: { $0 == "." })).trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { base = "tune" }
        let ext = "." + Rules.tuneExtension
        var name = base + ext
        var n = 2
        while taken.contains(name) {
            name = "\(base) (\(n))\(ext)"
            n += 1
        }
        return name
    }

    /// Whether a command's `name` names a tune: its name now, or its file
    /// stem, which it showed before its file was read.
    public static func names(_ name: String, tuneName: String, fileStem: String) -> Bool {
        name == tuneName || name == fileStem
    }

    /// Bytes still to download: each file's size less what is on disk of it,
    /// final or part.
    public static func needBytes(_ files: [(name: String, bytes: Int64)], present: [String: Int64]) -> Int64 {
        files.reduce(0) { $0 + max(0, $1.bytes - (present[$1.name] ?? 0)) }
    }

    static func isKeyScalar(_ u: Unicode.Scalar) -> Bool {
        ("A"..."Z").contains(u) || ("a"..."z").contains(u) || ("0"..."9").contains(u) || u == "#"
    }

    static func isControl(_ u: Unicode.Scalar) -> Bool {
        u.value <= 0x1F || (0x7F...0x9F).contains(u.value)
    }
}
