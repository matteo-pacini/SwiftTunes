import Testing
import TunesContract

@Suite struct TuneRulesTests {
    @Test(arguments: [
        ("", "A tune needs a name."),
        (" \t\n ", "A tune needs a name."),
        ("Blue\u{7}Lamp", "A name cannot hold control characters or line breaks."),
        ("Blue\nLamp", "A name cannot hold control characters or line breaks."),
        ("Blue\u{85}Lamp", "A name cannot hold control characters or line breaks."),
        ("Blue\u{7F}Lamp", "A name cannot hold control characters or line breaks."),
        (String(repeating: "x", count: 61), "A name is at most 60 characters; this one has 61."),
        (String(repeating: "é", count: 61), "A name is at most 60 characters; this one has 61."),
        ("\n" + String(repeating: "x", count: 61), "A name is at most 60 characters; this one has 61."),
    ])
    func refused(_ name: String, _ text: String) {
        #expect(TuneRules.nameError(name) == text)
    }

    @Test(arguments: [
        "Blue Lamp", String(repeating: "x", count: 60), String(repeating: "🎷", count: 60),
        "  " + String(repeating: "x", count: 60) + " \n", ".hidden", "A/B", "Exports",
    ])
    func accepted(_ name: String) {
        #expect(TuneRules.nameError(name) == nil)
    }

    @Test func emptinessComesBeforeControlsBeforeLength() {
        #expect(TuneRules.nameError("\u{1}" + String(repeating: "x", count: 70)) == "A name cannot hold control characters or line breaks.")
    }
}
