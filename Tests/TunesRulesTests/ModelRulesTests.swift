import Foundation
import Testing
import TunesContract
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

/// The contract's fields for the models: written, read back, and read as
/// their defaults from a snapshot that lacks them.
@Suite struct ModelContractTests {
    func snapshot() -> Snapshot {
        Snapshot(
            version: 1, setup: .downloading,
            download: Download(file: 1, files: 4, name: "language model", done: 10, total: 20, rate: 0, error: nil, model: "small"),
            need: Need(downloadBytes: 0, diskFreeBytes: 0, ramBytes: 0),
            genres: [], genre: nil, keptTotal: 0, composing: false, ahead: 2, player: .none, stopped: false, tune: nil,
            pos: 0, posAt: 0, queue: [], shuffle: true, repeat: .all, ended: false, roundLeft: 0, keep: 50, ready: 0,
            keptPlaying: false, canNext: false, job: nil, expect: nil, undo: nil,
            model: Model(name: "m", variant: "v", device: "d", state: .unloaded, since: 0, silenceS: nil, detail: nil,
                         failures: 0, retryAt: nil, ramUsedBytes: nil, ramFreeBytes: nil),
            error: nil,
            models: [ModelChoice(id: "small", name: "Small", variant: "0.6B Q8", fileBytes: 709_846_656, downloadBytes: 1,
                                 onDisk: false, ramBytes: 4 * GiB, suggested: true, chosen: true, downloading: true)],
            memoryBytes: 16 * GiB, sharedBytes: 3_671_093_888
        )
    }

    @Test func theyAreWrittenAndReadBack() throws {
        let s = snapshot()
        let data = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(Snapshot.self, from: data) == s)
        let dict = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(dict["memory_bytes"] as? Int64 == 16 * GiB && dict["shared_bytes"] as? Int64 == 3_671_093_888)
        let model = try #require((dict["models"] as? [[String: Any]])?.first)
        #expect(model["id"] as? String == "small" && model["file_bytes"] as? Int64 == 709_846_656)
        #expect(model["download_bytes"] as? Int64 == 1 && model["on_disk"] as? Bool == false && model["ram_bytes"] as? Int64 == 4 * GiB)
        #expect(model["suggested"] as? Bool == true && model["chosen"] as? Bool == true && model["downloading"] as? Bool == true)
        #expect((dict["download"] as? [String: Any])?["model"] as? String == "small")
    }

    @Test func absentTheyReadAsTheirDefaults() throws {
        var dict = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot())) as? [String: Any])
        for key in ["models", "memory_bytes", "shared_bytes"] { dict[key] = nil }
        var download = try #require(dict["download"] as? [String: Any])
        download["model"] = nil
        dict["download"] = download
        let old = try JSONDecoder().decode(Snapshot.self, from: try JSONSerialization.data(withJSONObject: dict))
        #expect(old.models.isEmpty && old.memoryBytes == 0 && old.sharedBytes == 0)
        #expect(old.download?.model == nil && old.download?.done == 10)
    }
}
