import Testing
import TunesContract

@Suite struct GenreRulesTests {
    static func fields(
        name: String = "Jazz", caption: String = "a jazz trio", turns: String = "",
        slowest: String = "70", fastest: String = "120"
    ) -> GenreFieldsText {
        GenreFieldsText(name: name, caption: caption, turns: turns, slowest: slowest, fastest: fastest)
    }

    static let long120 = String(repeating: "a", count: 120)
    static let long121 = String(repeating: "a", count: 121)

    @Test func validFieldsPass() {
        #expect(GenreRules.fieldError(Self.fields(), others: ["Lo-fi"]) == nil)
    }

    @Test(arguments: [
        ("", "A genre needs a name."),
        ("  \t\n ", "A genre needs a name."),
        ("Ja\u{7}zz", "A name cannot hold control characters or line breaks."),
        ("Ja\nzz", "A name cannot hold control characters or line breaks."),
        ("Ja\u{85}zz", "A name cannot hold control characters or line breaks."),
        ("Ja\u{7F}zz", "A name cannot hold control characters or line breaks."),
        ("Jazz/Funk", "A name cannot contain a slash: it is also a folder's name."),
        (".jazz", "A name cannot start with a dot."),
        ("  .jazz", "A name cannot start with a dot."),
        (String(repeating: "x", count: 41), "A name is at most 40 characters; this one has 41."),
        (String(repeating: "é", count: 41), "A name is at most 40 characters; this one has 41."),
        ("Exports", "Exports is the folder for exported copies; pick another name."),
        ("eXPORTS", "Exports is the folder for exported copies; pick another name."),
        ("lo-FI", "There is already a genre called Lo-fi."),
        (" Lo-fi ", "There is already a genre called Lo-fi."),
    ])
    func nameRules(name: String, text: String) {
        #expect(GenreRules.fieldError(Self.fields(name: name), others: ["Lo-fi"]) == Refusal(field: .name, text: text))
    }

    @Test(arguments: [String(repeating: "x", count: 40), String(repeating: "🎷", count: 40), "Exportss"])
    func namesAtTheLimitPass(name: String) {
        #expect(GenreRules.fieldError(Self.fields(name: name), others: []) == nil)
    }

    @Test func nameRulesComeBeforeCaption() {
        #expect(GenreRules.fieldError(Self.fields(name: "", caption: ""), others: [])?.field == .name)
    }

    @Test(arguments: [
        ("", "A genre needs a prompt."),
        (" \n", "A genre needs a prompt."),
        (String(repeating: "c", count: 401), "A prompt is at most 400 characters; this one has 401."),
    ])
    func captionRules(caption: String, text: String) {
        #expect(GenreRules.fieldError(Self.fields(caption: caption), others: []) == Refusal(field: .caption, text: text))
    }

    @Test func captionAtTheLimitPasses() {
        #expect(GenreRules.fieldError(Self.fields(caption: String(repeating: "c", count: 400)), others: []) == nil)
    }

    @Test(arguments: [
        (long121, "Line 1 is longer than 120 characters."),
        ("\n" + long121, "Line 2 is longer than 120 characters."),
        ("a\r\n\r\nb\r" + long121, "Line 4 is longer than 120 characters."),
        ("a\na\n" + long121, "Line 3 is longer than 120 characters."),
        ((1...21).map { "turn \($0)" }.joined(separator: "\n"), "At most 20 variations; this has 21."),
    ])
    func turnsRules(turns: String, text: String) {
        #expect(GenreRules.fieldError(Self.fields(turns: turns), others: []) == Refusal(field: .turns, text: text))
    }

    @Test(arguments: [
        long120,
        "  " + long120 + "  ",
        (1...20).map { "turn \($0)" }.joined(separator: "\n"),
        ((1...20).map { "turn \($0)" } + ["turn 1", "", "  "]).joined(separator: "\n"),
    ])
    func turnsWithinTheRulesPass(turns: String) {
        #expect(GenreRules.fieldError(Self.fields(turns: turns), others: []) == nil)
    }

    @Test(arguments: [
        ("", "120", "The slowest tempo needs a whole number."),
        ("7o", "120", "The slowest tempo needs a whole number."),
        ("70.5", "120", "The slowest tempo needs a whole number."),
        ("-70", "120", "The slowest tempo needs a whole number."),
        ("x", "y", "The slowest tempo needs a whole number."),
        ("70", "", "The fastest tempo needs a whole number."),
        ("70", "١٢٠", "The fastest tempo needs a whole number."),
        ("29", "120", "Tempos go from 30 to 300 BPM."),
        ("70", "301", "Tempos go from 30 to 300 BPM."),
        ("70", "99999999999999999999999", "Tempos go from 30 to 300 BPM."),
        ("121", "120", "The slowest tempo is above the fastest."),
    ])
    func bpmRules(slowest: String, fastest: String, text: String) {
        #expect(GenreRules.fieldError(Self.fields(slowest: slowest, fastest: fastest), others: []) == Refusal(field: .bpm, text: text))
    }

    @Test(arguments: [("30", "300"), (" 30 ", "30"), ("300", "300"), ("070", "120")])
    func bpmWithinTheRulesPass(slowest: String, fastest: String) {
        #expect(GenreRules.fieldError(Self.fields(slowest: slowest, fastest: fastest), others: []) == nil)
    }

    @Test func parseTurnsTrimsAndDropsBlanksAndRepeats() {
        let parsed = GenreRules.parseTurns(" a \n\nb\na\n  b  \r\nc")
        #expect(parsed.turns == ["a", "b", "c"])
        #expect(parsed.longLine == nil)
    }
}
