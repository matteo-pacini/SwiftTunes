import Foundation
import Testing
import TunesContract

@Suite struct WordsRulesTests {
    @Test func sungLinesSkipBlanksAndSectionMarks() {
        let words = "[Verse]\n  walking home \n\n[Chorus]\r\nunder the lights\r  [Bridge]  \nhold on"
        #expect(WordsRules.sungLines(words) == ["walking home", "under the lights", "hold on"])
        #expect(WordsRules.sungLines("") == [] && WordsRules.sungLines("[Instrumental]") == [])
    }

    @Test(arguments: [
        ("", "A tune needs at least one sung line."),
        ("   \n\n", "A tune needs at least one sung line."),
        ("[Verse]\n[Chorus]", "A tune needs at least one sung line."),
        ("la\n" + String(repeating: "x", count: 1998), "The words are at most 2,000 characters; these have 2,001."),
        (String(repeating: "é", count: 12345), "The words are at most 2,000 characters; these have 12,345."),
    ])
    func wordsErrors(_ words: String, _ text: String) {
        #expect(WordsRules.wordsError(words) == text)
    }

    @Test(arguments: ["hold on", "[Verse]\nhold on", String(repeating: "x", count: 2000)])
    func wordsAccepted(_ words: String) {
        #expect(WordsRules.wordsError(words) == nil)
    }

    @Test(arguments: [
        ("a\nb\nc\nd\ne", true),                  // 5 sung lines
        ("a\nb\nc\nd\ne\nf", false),              // 6, all different
        ("a\nb\nc\na\nB\nC", true),               // 6, but 3 different without case
        ("a\nb\nc\nd\nA\nB", false),              // 6, 4 different
        ("[Verse]\na\nb\n[Chorus]\nc\nd\ne", true),
        ("[Instrumental]", true),
    ])
    func thinWords(_ words: String, _ thin: Bool) {
        #expect(WordsRules.tooThin(words) == thin)
    }
}

@Suite struct NewFieldsDecodeTests {
    @Test func absentFieldsReadAsNotSung() throws {
        let genre = try JSONDecoder().decode(GenreSummary.self, from: Data(#"{"id": "j", "name": "J", "kept": 1, "palette": null}"#.utf8))
        #expect(!genre.sung)
        let job = try JSONDecoder().decode(Job.self, from: Data(#"{"stage": "writing", "started": 1, "expect_s": null, "written_s": null}"#.utf8))
        #expect(!job.sung && !job.ownWords && job.name == nil)
    }

    @Test func everyKeyIsWritten() throws {
        let job = Job(stage: .rendering, started: 2, expectS: nil, writtenS: 3, sung: true, ownWords: true, name: "Blue Lamp")
        let text = String(decoding: try JSONEncoder().encode(job), as: UTF8.self)
        #expect(text.contains(#""own_words":true"#) && text.contains(#""sung":true"#) && text.contains(#""name":"Blue Lamp""#))
        #expect(try JSONDecoder().decode(Job.self, from: Data(text.utf8)) == job)
        let tune = PlayingTune(name: "n", file: "f", bpm: nil, key: nil, length: nil, kept: true, new: false, pinned: false, pos: nil, wave: [], sung: false, lyrics: nil)
        let t = String(decoding: try JSONEncoder().encode(tune), as: UTF8.self)
        #expect(t.contains(#""lyrics":null"#) && t.contains(#""sung":false"#))
        let summary = String(decoding: try JSONEncoder().encode(GenreSummary(id: "j", name: "J", kept: 0, sung: true)), as: UTF8.self)
        #expect(summary.contains(#""sung":true"#))
    }
}

@Suite struct NeedDecodeTests {
    @Test func onDiskBytesReadsAsZeroWhenAbsentAndIsWritten() throws {
        let old = try JSONDecoder().decode(Need.self, from: Data(#"{"download_bytes": 1, "disk_free_bytes": 2, "ram_bytes": 3}"#.utf8))
        #expect(old.onDiskBytes == 0)
        let text = String(decoding: try JSONEncoder().encode(Need(downloadBytes: 1, diskFreeBytes: 2, ramBytes: 3, onDiskBytes: 4)), as: UTF8.self)
        #expect(text.contains(#""on_disk_bytes":4"#))
    }
}
