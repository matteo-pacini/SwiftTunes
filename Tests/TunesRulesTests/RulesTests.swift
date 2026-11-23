import Foundation
import Testing
import TunesContract
@testable import TunesRules

private let S = 35847

/// Codes: ("m", n) n distinct non-silent codes, ("s", n) n silent ones.
private func codes(_ parts: (String, Int)...) -> [Int] {
    parts.flatMap { kind, n in kind == "s" ? Array(repeating: S, count: n) : (0..<n).map { 1000 + $0 } }
}

@Suite struct SilenceTests {
    @Test(arguments: [
        ("a 2 s tail is cut where it starts", codes(("m", 50), ("s", 10)), PlanVerdict(cut: 10, rewrite: nil)),
        ("a 0.8 s tail is left", codes(("m", 56), ("s", 4)), PlanVerdict(cut: nil, rewrite: nil)),
        ("exactly 1 s of tail is cut", codes(("m", 55), ("s", 5)), PlanVerdict(cut: 11, rewrite: nil)),
        ("5 s in the middle is allowed", codes(("m", 10), ("s", 25), ("m", 25)), PlanVerdict(cut: nil, rewrite: nil)),
        ("5.2 s in the middle rewrites", codes(("m", 10), ("s", 26), ("m", 24), ("s", 10)), PlanVerdict(cut: 12, rewrite: 5.2)),
        ("the longest bad run is reported", codes(("s", 30), ("m", 5), ("s", 40), ("m", 5)), PlanVerdict(cut: nil, rewrite: 8)),
        ("a leading run counts as the middle", codes(("s", 30), ("m", 30)), PlanVerdict(cut: nil, rewrite: 6)),
    ])
    func verdict(_ what: String, codes: [Int], want: PlanVerdict) {
        #expect(Silence.verdict(codes, silence: S) == want, "\(what)")
    }

    @Test func codesInTheServersFormat() throws {
        #expect(try Silence.parseCodes("12,35847,7,") == [12, 35847, 7])
    }

    @Test(arguments: [",", "", "1,x,", nil] as [String?])
    func noCodes(_ text: String?) {
        #expect(throws: Silence.NoCodes.self) { try Silence.parseCodes(text) }
    }
}

@Suite struct DelayTests {
    @Test(arguments: [(1, 3.0), (2, 30.0), (3, 30.0), (9, 30.0)])
    func retry(failures: Int, seconds: Double) {
        #expect(Rules.retryDelay(failures: failures) == seconds)
    }
}

@Suite struct FileNameTests {
    static let when: Date = {
        var c = DateComponents()
        (c.year, c.month, c.day, c.hour, c.minute, c.second) = (2026, 11, 22, 21, 5, 9)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: c)!
    }()

    @Test(arguments: [
        ("C# minor", "20261122-210509-88bpm-C#-minor.m4a"),
        ("", "20261122-210509-88bpm-unknown.m4a"),
        (nil, "20261122-210509-88bpm-unknown.m4a"),
        ("  F  major!", "20261122-210509-88bpm-F-major.m4a"),
    ] as [(String?, String)])
    func composed(key: String?, name: String) {
        #expect(TuneFiles.fileName(at: Self.when, timeZone: TimeZone(identifier: "UTC")!, bpm: 88, key: key) == name)
    }

    @Test func parsed() throws {
        let p = try #require(TuneFiles.parse("20261122-210509-88bpm-C#-minor.m4a"))
        #expect(p.bpm == 88 && p.key == "C# minor")
    }

    @Test(arguments: [
        "notes.m4a", "20261122-210509-88bpm-C#-minor.m4a.bak", "x20261122-210509-88bpm-A-major.m4a",
        "20261122-210509-88bpm-C#-minor.mp3", "20261122-210509-1234bpm-A.m4a", "20261122-210509-88bpm-.m4a",
        "20261122-210509-88bpm-A--major.m4a", "20261122-210509-88bpm-A-.m4a", "2026112-210509-88bpm-A.m4a",
        ".20261122-210509-88bpm-A.m4a.pin",
    ])
    func foreignNamesAreNotOurs(_ name: String) {
        #expect(TuneFiles.parse(name) == nil)
    }
}

@Suite struct KeepTests {
    static let names = (1...7).map { "2026010\($0)-000000-80bpm-A-major.m4a" } + ["mine.m4a", "notes.txt"]

    @Test func oldestFirstOnlyOurs() {
        #expect(TuneFiles.keepVictims(Self.names, keep: 4, protected: []) == Array(Self.names[0..<3]))
    }

    @Test func protectedAreCountedNeverDeleted() {
        let n = Self.names
        #expect(TuneFiles.keepVictims(n, keep: 4, protected: [n[0], n[2]]) == [n[1], n[3], n[4]])
    }

    @Test func underTheLimit() {
        #expect(TuneFiles.keepVictims(Array(Self.names[0..<3]) + ["mine.m4a"], keep: 4, protected: []).isEmpty)
    }

    @Test func pinnedAreNeitherCountedNorDeleted() {
        let n = Self.names
        #expect(TuneFiles.keepVictims(n, keep: 4, protected: [], pinned: [n[0], n[1]]) == [n[2]])
    }

    @Test func pinMarkIsHiddenAndNotATune() {
        let mark = TuneFiles.pinMark(Self.names[0])
        #expect(mark == ".20260101-000000-80bpm-A-major.m4a.pin")
        #expect(!TuneFiles.isTune(mark))
    }
}

@Suite struct ExportNameTests {
    @Test(arguments: [
        ("Jazz", "Lazy Avenue", [], "Jazz - Lazy Avenue.m4a"),
        ("Jazz", "Lazy Avenue", ["Jazz - Lazy Avenue.m4a", "Jazz - Lazy Avenue (2).m4a"], "Jazz - Lazy Avenue (3).m4a"),
        ("Jazz", "A/B\nC", [], "Jazz - A-BC.m4a"),
        (".x", "y", [], "x - y.m4a"),
        ("", "", [], "-.m4a"),
    ] as [(String, String, [String], String)])
    func names(genre: String, title: String, taken: [String], want: String) {
        #expect(TuneFiles.exportName(genre: genre, title: title, taken: Set(taken)) == want)
    }
}

@Suite struct NeedBytesTests {
    @Test func countsWhatIsLeft() {
        let files: [(name: String, bytes: Int64)] = [("a", 100), ("b", 50), ("c", 10)]
        #expect(TuneFiles.needBytes(files, present: ["a": 40, "b": 50, "c": 99]) == 60)
        #expect(TuneFiles.needBytes(files, present: [:]) == 160)
    }
}

@Suite struct LevelsTests {
    static let loud: [Float] = (0..<4000).flatMap { _ in [Float(8000) / 32768, -Float(8000) / 32768] }
    static let quiet = [Float](repeating: 0, count: 8000)

    @Test func aToneAndSilence() {
        let lv = Levels.db(Array(Self.loud.prefix(800)) + Array(Self.quiet.prefix(800)))
        #expect(lv.map { $0.rounded() } == [(20 * log10(8000.0 / 32768)).rounded(), -120])
    }

    @Test func sixQuietSecondsInTheMiddleTrip() {
        let samples = Self.loud + Array(repeating: Self.quiet, count: 6).flatMap { $0 } + Self.loud + Self.quiet + Self.quiet
        #expect(Timings.tenth(Levels.quietMidRun(Levels.db(samples))) == 6.0)
    }

    @Test func aQuietTailDoesNotCount() {
        let samples = Self.loud + Array(repeating: Self.quiet, count: 7).flatMap { $0 }
        #expect(Levels.quietMidRun(Levels.db(samples)) == 0)
    }

    @Test func underTheLimit() {
        let samples = Self.loud + [Float](repeating: 0, count: 39200) + Self.loud
        #expect(Levels.quietMidRun(Levels.db(samples)) <= Rules.quietMax)
    }

    @Test func waveHas78NormalisedBars() {
        let w = Levels.wave([Float](repeating: 100, count: 780) + [Float](repeating: 50, count: 780))
        #expect(w.count == 78)
        #expect(w.max() == 1.0 && w.first == 1.0 && w.last == 0.5)
    }

    @Test func silenceIsZeros() {
        #expect(Levels.wave([Float](repeating: 0, count: 1000)) == [Double](repeating: 0, count: 78))
    }

    @Test(arguments: [[Float](), [5, 9]])
    func fewSamples(_ samples: [Float]) {
        #expect(Levels.wave(samples).count == 78)
    }
}

@Suite struct MultipartTests {
    @Test func theAudioPart() throws {
        let body = Data(("--ace-batch-boundary\r\nContent-Type: audio/wav\r\n\r\nRIFFxx\r\n--ace-batch-boundary\r\n"
            + "Content-Type: application/octet-stream\r\nContent-Disposition: form-data; name=\"latent\"\r\n\r\n").utf8)
            + Data([0, 1]) + Data("\r\n--ace-batch-boundary--\r\n".utf8)
        #expect(try Multipart.audio(body) == Data("RIFFxx".utf8))
    }

    @Test func binaryAudioWithCRLFInside() throws {
        let audio = Data([0x52, 0x0D, 0x0A, 0x2D, 0x00, 0xFF])
        let body = Data("--b\r\ncontent-type: Audio/WAV\r\n\r\n".utf8) + audio + Data("\r\n--b--\r\n".utf8)
        #expect(try Multipart.audio(body) == audio)
    }

    @Test(arguments: [
        ("--b\r\nContent-Type: application/json\r\n\r\n{}\r\n--b--\r\n", Multipart.Failure.noAudioPart),
        ("RIFF....", Multipart.Failure.notMultipart),
        ("--no-line-end", Multipart.Failure.notMultipart),
    ])
    func refused(_ body: String, _ failure: Multipart.Failure) {
        #expect(throws: failure) { try Multipart.audio(Data(body.utf8)) }
    }
}

@Suite struct TimingTests {
    @Test(arguments: [([120.0, 104, 111], 111.0), ([100.0, 110, 130, 90], 105.0)] as [([Double], Double?)])
    func median(_ values: [Double], _ want: Double?) {
        #expect(Timings.median(values) == want)
    }

    @Test func medianOfNone() { #expect(Timings.median([]) == nil) }

    @Test func theLastFiveKept() {
        #expect(Timings.adding(6.04, to: [1, 2, 3, 4, 5]) == [2, 3, 4, 5, 6.0])
    }

    @Test func expectNilUntilBothTimed() {
        #expect(Timings.expect(writing: [], rendering: []) == nil)
        #expect(Timings.expect(writing: [60], rendering: []) == nil)
        #expect(Timings.expect(writing: [60, 70, 80], rendering: [40, 50]) == Expect(writingS: 70, renderingS: 45))
    }

    @Test(arguments: [
        (#"{"writing": [60.5, 70], "rendering": [40]}"#, SavedState(writing: [60.5, 70], rendering: [40])),
        (#"{"writing": ["x"], "rendering": 4}"#, SavedState()),
        (#"{"counter": 7}"#, SavedState()),
        (#"{"writing": [1, 2, 3, 4, 5, 6, 7]}"#, SavedState(writing: [3, 4, 5, 6, 7])),
        (#"{"writing": [-1]}"#, SavedState()),
        ("not json", SavedState()),
        (#"{"shuffle": false, "repeat": "one", "writing": [1]}"#, SavedState(writing: [1], shuffle: false, repeat: .one)),
        (#"{"shuffle": 0, "repeat": "twice"}"#, SavedState()),
    ])
    func stateFileReadBack(_ text: String, _ want: SavedState) {
        #expect(SavedState.parse(text) == want)
    }

    @Test func stateFileMissingReadsAsDefaults() {
        #expect(SavedState.parse(nil) == SavedState(shuffle: true, repeat: .all))
    }

    @Test func stateFileRoundTrips() {
        let s = SavedState(writing: [33.3, 35], rendering: [31.8], shuffle: false, repeat: .off)
        #expect(s.text == #"{"writing": [33.3, 35.0], "rendering": [31.8], "shuffle": false, "repeat": "off"}"# + "\n")
        #expect(SavedState.parse(s.text) == s)
    }
}

@Suite struct DownloadRulesTests {
    @Test(arguments: [(nil, 100, 0), (0, 100, 0), (40, 100, 40), (100, 100, 100), (101, 100, 0)] as [(Int64?, Int64, Int64)])
    func resume(part: Int64?, expected: Int64, offset: Int64) {
        #expect(DownloadRules.resumeOffset(partBytes: part, expected: expected) == offset)
    }

    @Test func rangeHeader() {
        #expect(DownloadRules.rangeHeader(offset: 0) == nil)
        #expect(DownloadRules.rangeHeader(offset: 459083776) == "bytes=459083776-")
    }

    @Test(arguments: [(0, 200, false), (10, 206, true), (10, 200, false), (0, 206, false)])
    func resumes(offset: Int64, status: Int, want: Bool) {
        #expect(DownloadRules.resumes(offset: offset, status: status) == want)
    }

    @Test func rateOverTheLastTwoSeconds() {
        var w = RateWindow()
        #expect(w.add(1000, at: 10) == 2000)   // span floored at 0.5 s
        #expect(w.add(1000, at: 11) == 2000)   // 2000 bytes over 1 s
        #expect(w.add(1000, at: 12) == 1500)   // 3000 bytes over 2 s
        #expect(w.add(1000, at: 13.5) == 2000 / 1.5) // the blocks at 10 and 11 fell out
    }

    @Test func errorTexts() {
        #expect(DownloadRules.httpError(file: "vae-BF16.gguf", status: 404) == "vae-BF16.gguf: HTTP 404")
        #expect(DownloadRules.shortError(file: "x", got: 5, expected: 9) == "x: got 5 of 9 bytes")
        #expect(DownloadRules.checksumError(file: "x") == "x: checksum mismatch")
        #expect(DownloadRules.brokeError(file: "x", kind: "timed out") == "x: the connection broke (timed out)")
    }
}

@Suite struct ServerLogTests {
    @Test func theMetalDevice() {
        #expect(ServerLog.metalDevice("ggml_metal_device_init: GPU name:   MTL0 (Apple M4 Pro)") == "Apple M4 Pro")
        #expect(ServerLog.metalDevice("ggml_metal_device_init: GPU name:   MTL1 (Other)") == nil)
        #expect(ServerLog.metalDevice("[Load] LM backend: MTL0") == nil)
    }

    @Test func missingDevice() {
        let lines = ["ggml_metal_device_init: GPU name:   MTL0 (Apple M4 Pro)", "--device MTL0 not found. Available: BLAS CPU"]
        #expect(ServerLog.saysNoDevice(lines))
        #expect(ServerLog.missingDevice(lines) == "the server offers only BLAS CPU")
        #expect(ServerLog.missingDevice([]) == "the server listed no MTL0")
    }

    @Test func exitText() {
        #expect(ServerLog.exited(status: 1, lines: ["ok", "GGML ASSERT failed: x", "bye"]) == "the model server exited (status 1): GGML ASSERT failed: x")
        #expect(ServerLog.exited(status: 9, lines: ["ok"]) == "the model server exited (status 9)")
    }

    @Test func lifelinePID() {
        #expect(ServerLog.serverPID("tunes-lifeline: started 4242") == 4242)
        #expect(ServerLog.serverPID("other") == nil)
        // Never a pid that would signal every process (-1) or the caller's group (0).
        for bad in ["1", "0", "-1", "-4242", "x"] {
            #expect(ServerLog.serverPID("tunes-lifeline: started \(bad)") == nil)
        }
    }
}
