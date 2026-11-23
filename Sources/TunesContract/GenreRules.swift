import Foundation

/// The genre validation shared by the engine and the panel.
public enum GenreRules {
    public static let nameMax = 40
    public static let captionMax = 400
    public static let turnsMax = 20
    public static let turnMax = 120
    public static let bpmRange = 30...300
    /// The folder under `~/Music/Tunes` that holds exported copies; no genre
    /// may take its name, in any case.
    public static let exports = "Exports"

    /// The first rule the fields break, in the panel's order, or nil.
    /// `others` are the names of the other genres, for the duplicate rule.
    ///
    /// Names, captions and lines are trimmed of Unicode whitespace and
    /// counted in Unicode scalars. "Line N" counts the lines as typed,
    /// blank and repeated ones included. Names compare without case.
    public static func fieldError(_ fields: GenreFieldsText, others: [String]) -> Refusal? {
        if let text = nameError(trim(fields.name), others: others) {
            return Refusal(field: .name, text: text)
        }
        let caption = trim(fields.caption)
        if caption.isEmpty {
            return Refusal(field: .caption, text: "A genre needs a prompt.")
        }
        let captionCount = caption.unicodeScalars.count
        if captionCount > captionMax {
            return Refusal(field: .caption, text: "A prompt is at most \(captionMax) characters; this one has \(captionCount).")
        }
        let parsed = parseTurns(fields.turns)
        if let line = parsed.longLine {
            return Refusal(field: .turns, text: "Line \(line) is longer than \(turnMax) characters.")
        }
        if parsed.turns.count > turnsMax {
            return Refusal(field: .turns, text: "At most \(turnsMax) variations; this has \(parsed.turns.count).")
        }
        let lo = wholeNumber(fields.slowest)
        let hi = wholeNumber(fields.fastest)
        guard let lo, let hi else {
            let which = lo == nil ? "slowest" : "fastest"
            return Refusal(field: .bpm, text: "The \(which) tempo needs a whole number.")
        }
        if !bpmRange.contains(lo) || !bpmRange.contains(hi) {
            return Refusal(field: .bpm, text: "Tempos go from \(bpmRange.lowerBound) to \(bpmRange.upperBound) BPM.")
        }
        if lo > hi {
            return Refusal(field: .bpm, text: "The slowest tempo is above the fastest.")
        }
        return nil
    }

    /// The text trimmed as both sides trim it.
    public static func trim(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The variations as saved: each line trimmed, blank and repeated lines
    /// dropped, order kept. `longLine` is the 1-based number, among the
    /// lines as typed, of the first kept line over the limit.
    public static func parseTurns(_ text: String) -> (turns: [String], longLine: Int?) {
        var turns: [String] = []
        var longLine: Int?
        for (i, raw) in lines(text).enumerated() {
            let t = trim(raw)
            if t.isEmpty || turns.contains(t) { continue }
            if longLine == nil && t.unicodeScalars.count > turnMax {
                longLine = i + 1
            }
            turns.append(t)
        }
        return (turns, longLine)
    }

    /// A tempo box's text as a whole number: ASCII digits only, after
    /// trimming; nil otherwise.
    public static func wholeNumber(_ text: String) -> Int? {
        let t = trim(text)
        guard !t.isEmpty, t.unicodeScalars.allSatisfy({ $0.value >= 0x30 && $0.value <= 0x39 }) else {
            return nil
        }
        // Digits beyond Int's range are no tempo either; they fail the range rule.
        return Int(t) ?? Int.max
    }

    private static func nameError(_ name: String, others: [String]) -> String? {
        if name.isEmpty { return "A genre needs a name." }
        if name.unicodeScalars.contains(where: isControl) {
            return "A name cannot hold control characters or line breaks."
        }
        if name.contains("/") { return "A name cannot contain a slash: it is also a folder's name." }
        if name.hasPrefix(".") { return "A name cannot start with a dot." }
        let count = name.unicodeScalars.count
        if count > nameMax { return "A name is at most \(nameMax) characters; this one has \(count)." }
        if name.lowercased() == exports.lowercased() {
            return "\(exports) is the folder for exported copies; pick another name."
        }
        if let other = others.first(where: { $0.lowercased() == name.lowercased() }) {
            return "There is already a genre called \(other)."
        }
        return nil
    }

    /// C0 and C1 controls and DEL.
    private static func isControl(_ s: Unicode.Scalar) -> Bool {
        s.value <= 0x1F || (0x7F...0x9F).contains(s.value)
    }

    /// Splits on CRLF, CR or LF, as typed text may hold any of them.
    private static func lines(_ text: String) -> [String] {
        var out: [String] = []
        var current = String.UnicodeScalarView()
        var scalars = text.unicodeScalars.makeIterator()
        var pendingCR = false
        while let s = scalars.next() {
            if pendingCR {
                pendingCR = false
                if s == "\n" { continue }
            }
            if s == "\r" || s == "\n" {
                out.append(String(current))
                current = String.UnicodeScalarView()
                pendingCR = s == "\r"
            } else {
                current.append(s)
            }
        }
        out.append(String(current))
        return out
    }
}

/// The fields as typed: tempos are text until they parse.
public struct GenreFieldsText: Sendable, Equatable {
    public var name: String
    public var caption: String
    /// One per line.
    public var turns: String
    public var slowest: String
    public var fastest: String

    public init(name: String, caption: String, turns: String, slowest: String, fastest: String) {
        self.name = name
        self.caption = caption
        self.turns = turns
        self.slowest = slowest
        self.fastest = fastest
    }
}
