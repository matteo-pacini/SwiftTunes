import Foundation

/// The rules for a sung tune's words, shared by the engine and the panel.
public enum WordsRules {
    public static let max = 2000

    /// Non-empty lines that do not start with "[", trimmed: the lines that
    /// are sung rather than marking a section.
    public static func sungLines(_ words: String) -> [String] {
        lines(words).map(GenreRules.trim).filter { !$0.isEmpty && !$0.hasPrefix("[") }
    }

    /// For words the user wrote: `A tune needs at least one sung line.` or
    /// `The words are at most 2,000 characters; these have N.`, else nil.
    /// Characters are counted as Unicode scalars, as the other rules count.
    public static func wordsError(_ words: String) -> String? {
        if sungLines(words).isEmpty { return "A tune needs at least one sung line." }
        let count = words.unicodeScalars.count
        if count > max { return "The words are at most \(grouped(max)) characters; these have \(grouped(count))." }
        return nil
    }

    /// For words the model wrote: fewer than 6 sung lines, or fewer than 4
    /// different ones compared without case.
    public static func tooThin(_ words: String) -> Bool {
        let sung = sungLines(words)
        return sung.count < 6 || Set(sung.map { $0.lowercased() }).count < 4
    }

    /// A count with a comma every three digits, as the sentences write them.
    static func grouped(_ n: Int) -> String {
        let digits = Array(String(n))
        var out = ""
        for (i, d) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(d)
        }
        return out
    }

    /// Splits on CRLF, CR or LF.
    static func lines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }
}
