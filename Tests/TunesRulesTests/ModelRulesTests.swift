import Testing
@testable import TunesRules

private let GiB: Int64 = 1 << 30

/// The two models as `Config/pins.json` lists them, smallest first.
private let ids = ["small", "large"]
private let from: [Int64] = [0, 24 * GiB]
private let own: [(name: String, bytes: Int64)] = [
    ("acestep-5Hz-lm-0.6B-Q8_0.gguf", 709_846_656), ("acestep-5Hz-lm-4B-Q8_0.gguf", 4_457_323_648),
]
private let shared: [(name: String, bytes: Int64)] = [
    ("acestep-v15-turbo-Q8_0.gguf", 2_549_528_000), ("Qwen3-Embedding-0.6B-Q8_0.gguf", 784_144_960), ("vae-BF16.gguf", 337_420_928),
]

@Suite struct ModelRulesTests {
    @Test(arguments: [(8, "small"), (16, "small"), (24, "large"), (32, "large"), (64, "large")] as [(Int64, String)])
    func suggestion(memoryGiB: Int64, want: String) {
        #expect(ids[ModelRules.suggested(from: from, memory: memoryGiB * GiB)] == want)
    }

    @Test func justUnder24GiBIsSmall() {
        #expect(ModelRules.suggested(from: from, memory: 24 * GiB - 1) == 0)
    }

    @Test func noThresholdReachedSuggestsTheFirst() {
        #expect(ModelRules.suggested(from: [GiB, 2 * GiB], memory: 0) == 0)
    }

    @Test func eachChoiceDownloadsItsOwnFileAndTheSharedOnes() {
        let none: [String: Int64] = [:]
        #expect(TuneFiles.needBytes([own[0]] + shared, present: none) == 4_380_940_544)
        #expect(TuneFiles.needBytes([own[1]] + shared, present: none) == 8_128_417_536)
        // With one model on disk, the other is its own file only.
        let small = Dictionary(uniqueKeysWithValues: ([own[0]] + shared).map { ($0.name, $0.bytes) })
        #expect(TuneFiles.needBytes([own[1]] + shared, present: small) == 4_457_323_648)
    }

    @Test(arguments: [
        // Nothing on disk: the saved one, else the suggested one.
        (nil, [false, false], 0, 0),
        (nil, [false, false], 1, 1),
        ("large", [false, false], 0, 1),
        // A state file without a model: the one on disk, Large when both are.
        (nil, [true, false], 1, 0),
        (nil, [false, true], 0, 1),
        (nil, [true, true], 0, 1),
        // The saved one while it is on disk.
        ("small", [true, true], 1, 0),
        ("large", [true, true], 0, 1),
        // A saved one no longer on disk gives way to the one that is.
        ("small", [false, true], 0, 1),
        ("large", [true, false], 1, 0),
        // An id the pins do not list counts as none saved.
        ("medium", [false, false], 1, 1),
        ("medium", [true, false], 1, 0),
    ] as [(String?, [Bool], Int, Int)])
    func chosen(saved: String?, onDisk: [Bool], suggested: Int, want: Int) {
        #expect(ModelRules.chosen(saved: saved, ids: ids, onDisk: onDisk, suggested: suggested) == want)
    }
}
