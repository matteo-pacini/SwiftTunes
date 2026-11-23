import Testing
@testable import TunesPanel

@Suite("Formats")
struct FormatTests {
    @Test("clock", arguments: [
        (0.0, "0:00"), (84, "1:24"), (172.4, "2:52"), (59.99, "0:59"), (725, "12:05"), (-1, "–:––"),
    ] as [(Double, String)])
    func clock(_ seconds: Double, _ text: String) {
        #expect(Format.clock(seconds) == text)
    }

    @Test func clockOfNothing() {
        #expect(Format.clock(nil) == "–:––")
    }

    static let G = 1_073_741_824.0

    @Test("GiB", arguments: [
        (6 * G, 1, "6 GiB"), (8 * G, 1, "8 GiB"), (19.3 * G, 1, "19.3 GiB"), (7.57 * G, 2, "7.57 GiB"), (226.4 * G, 1, "226 GiB"),
    ] as [(Double, Int, String)])
    func gib(_ bytes: Double, _ decimals: Int, _ text: String) {
        #expect(Format.gib(Int64(bytes), decimals: decimals) == text)
    }

    @Test("rate", arguments: [(28_400_000.0, "28 MB/s"), (640_000, "640 kB/s")] as [(Double, String)])
    func rate(_ bps: Double, _ text: String) {
        #expect(Format.rate(bps) == text)
    }

    @Test("size", arguments: [(4_128_768 as Int64, "4.1 MB"), (980_000, "980 kB"), (200, "1 kB")])
    func size(_ bytes: Int64, _ text: String) {
        #expect(Format.size(bytes) == text)
    }

    @Test("home as ~", arguments: [
        ("/Users/someone/Music/Tunes/a b.m4a", "/Users/someone", "~/Music/Tunes/a b.m4a"),
        ("/Users/someone", "/Users/someone/", "~"),
        ("/Users/someoneelse/x", "/Users/someone", "/Users/someoneelse/x"),
        ("/tmp/x", "", "/tmp/x"),
    ])
    func tilde(_ path: String, _ home: String, _ text: String) {
        #expect(Format.tilde(path, home: home) == text)
    }

    @Test("the waveform: 78 levels, resampled by index, clamped")
    func wave() {
        #expect(Decide.waveLevels([]) == Array(repeating: 0, count: 78))
        let half = Decide.waveLevels([0, 1])
        #expect(half.count == 78)
        #expect([half[0], half[38], half[39], half[77]] == [0, 0, 1, 1])
        #expect(Decide.waveLevels(Array(repeating: 2, count: 78)).allSatisfy { $0 == 1 })
        #expect(Decide.waveLevels([-1, .nan]).allSatisfy { $0 == 0 })
    }
}
