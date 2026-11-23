import Foundation
import Testing
import TunesContract
@testable import TunesRules

private let K = (1...6).map { "2026010\($0)-000000-90bpm-C-major.m4a" }

/// Tunes in the order they would play, `n` of them: choose, start (a wrap
/// empties what was played), the next chosen while it plays.
private func playRounds(
    _ kept: [String], shuffle: Bool, repeat mode: RepeatMode, _ n: Int, seed: UInt64 = 5,
    anchor: String? = nil, played: Set<String> = []
) -> [String] {
    var rng = SplitMix64(seed: seed)
    var out: [String] = []
    var played = played
    var anchor = anchor
    var current: String?
    for _ in 0..<n {
        let (next, wraps) = Rounds.choose(
            kept: kept, played: played, busy: current.map { [$0] } ?? [], shuffle: shuffle, anchor: anchor,
            repeat: mode, rng: &rng
        )
        guard let next else { break }
        if wraps { played = [] }
        played.insert(next)
        anchor = next
        current = next
        out.append(next)
    }
    return out
}

@Suite struct RoundTests {
    @Test func allLeftAtTheStartOldestFirst() {
        #expect(Rounds.left(kept: K.reversed(), played: [], shuffle: false, anchor: nil) == K)
    }

    @Test func playedAndBusyAreNotLeft() {
        #expect(Rounds.left(kept: K, played: [K[0], K[3]], shuffle: true, anchor: nil, busy: [K[5]]) == [K[1], K[2], K[4]])
    }

    @Test func shuffleOffGoesOnFromTheAnchor() {
        #expect(Rounds.left(kept: K, played: [K[2]], shuffle: false, anchor: K[2]) == Array(K[3...]) + Array(K[..<2]))
    }

    @Test func shuffleOnIgnoresTheAnchor() {
        #expect(Rounds.left(kept: K, played: [K[2]], shuffle: true, anchor: K[2]) == [K[0], K[1]] + Array(K[3...]))
    }

    @Test func anAnchorWhoseFileIsGoneStillPlacesTheOrder() {
        #expect(Rounds.left(kept: Array(K[..<2]) + Array(K[3...]), played: [K[1]], shuffle: false, anchor: K[2])
            == Array(K[3...]) + [K[0]])
    }

    @Test func orderMadeThenRoundAgain() {
        #expect(playRounds(K.reversed(), shuffle: false, repeat: .all, 14) == Array((K + K + K).prefix(14)))
    }

    @Test(arguments: [1, 5, 9, 42] as [UInt64])
    func shufflePlaysEachTuneOnceARoundAndNeverTwiceInARow(seed: UInt64) {
        let got = playRounds(K, shuffle: true, repeat: .all, 60, seed: seed)
        #expect(got.count == 60)
        for i in stride(from: 0, to: 60, by: 6) {
            #expect(Array(got[i..<(i + 6)]).sorted() == K)
        }
        #expect(Set(stride(from: 0, to: 60, by: 6).map { got[$0..<($0 + 6)].joined() }).count > 1)
        #expect(zip(got, got.dropFirst()).allSatisfy { $0 != $1 })
    }

    @Test func repeatOffPlaysOneRound() {
        #expect(playRounds(K, shuffle: true, repeat: .off, 20, seed: 9).count == 6)
        #expect(playRounds(K, shuffle: false, repeat: .off, 20) == K)
    }

    @Test func repeatOffWithTheRoundOverChoosesNothing() {
        var rng = SplitMix64(seed: 1)
        let r = Rounds.choose(kept: K, played: Set(K), busy: [], shuffle: true, anchor: nil, repeat: .off, rng: &rng)
        #expect(r.tune == nil && !r.wraps)
    }

    @Test func repeatOneWrapsAsRepeatAllDoes() {
        var rng = SplitMix64(seed: 1)
        let r = Rounds.choose(kept: K, played: Set(K), busy: [K[5]], shuffle: false, anchor: K[5], repeat: .one, rng: &rng)
        #expect(r.tune == K[0] && r.wraps)
    }

    @Test func aNewRoundDoesNotStartWithThePlayingTune() {
        var rng = SplitMix64(seed: 1)
        let r = Rounds.choose(kept: Array(K[..<2]), played: Set(K[..<2]), busy: [K[0]], shuffle: true, anchor: nil, repeat: .all, rng: &rng)
        #expect(r.tune == K[1] && r.wraps)
    }

    @Test func oneKeptTunePlayingLeavesNothing() {
        var rng = SplitMix64(seed: 1)
        let r = Rounds.choose(kept: [K[0]], played: [K[0]], busy: [K[0]], shuffle: true, anchor: nil, repeat: .all, rng: &rng)
        #expect(r.tune == nil && !r.wraps)
        let none = Rounds.choose(kept: [], played: [], busy: [], shuffle: true, anchor: nil, repeat: .all, rng: &rng)
        #expect(none.tune == nil && !none.wraps)
    }

    @Test func shuffleSwitchedOffMidRound() {
        #expect(playRounds(K, shuffle: false, repeat: .off, 10, anchor: K[2], played: [K[2], K[4]]) == [K[3], K[5], K[0], K[1]])
        #expect(playRounds(K, shuffle: false, repeat: .off, 10, anchor: K[4], played: [K[2], K[4]]) == [K[5], K[0], K[1], K[3]])
    }

    @Test func shuffleSwitchedOnMidRoundPlaysTheRestOnce() {
        #expect(playRounds(K, shuffle: true, repeat: .off, 10, anchor: K[2], played: [K[2], K[4]]).sorted() == [K[0], K[1], K[3], K[5]])
    }

    @Test func aNewTuneJoinsTheEndOfTheOrder() {
        let new = "20260201-000000-90bpm-C-major.m4a"
        #expect(playRounds(K + [new], shuffle: false, repeat: .all, 12, anchor: K[1], played: [K[0], K[1], new])
            == Array(K[2...]) + K + [new, K[0]])
    }

    struct QueueCase: Sendable, CustomTestStringConvertible {
        var what: String
        var kept: [String]
        var played: Set<String>
        var busy: Set<String>
        var anchor: String
        var mode: RepeatMode
        var first: String
        var wraps: Bool
        var want: [String]
        var testDescription: String { what }
    }

    static let queueCases: [QueueCase] = [
        QueueCase(what: "the three in order after the next", kept: K, played: [K[0]], busy: [K[0]], anchor: K[0], mode: .all, first: K[1], wraps: false, want: [K[2], K[3]]),
        QueueCase(what: "repeat off stops at the end of the round", kept: K, played: Set(K[..<4]), busy: [K[3]], anchor: K[3], mode: .off, first: K[4], wraps: false, want: [K[5]]),
        QueueCase(what: "repeat all wraps to the start", kept: K, played: Set(K[..<4]), busy: [K[3]], anchor: K[3], mode: .all, first: K[4], wraps: false, want: [K[5], K[0]]),
        QueueCase(what: "after a wrapping next, the new round's order", kept: K, played: Set(K), busy: [K[5]], anchor: K[5], mode: .all, first: K[0], wraps: true, want: [K[1], K[2]]),
        QueueCase(what: "never the next twice, nor the playing one", kept: Array(K[..<2]), played: [K[0]], busy: [K[0]], anchor: K[0], mode: .all, first: K[1], wraps: false, want: []),
    ]

    @Test(arguments: queueCases)
    func queueShowsTheKeptAfterTheNext(_ c: QueueCase) {
        #expect(Rounds.after(kept: c.kept, played: c.played, busy: c.busy, anchor: c.anchor, repeat: c.mode, first: c.first, wraps: c.wraps, count: 2) == c.want)
    }
}

@Suite struct ComposingTests {
    static let genre = Genre(id: "lofi", name: "Lo-fi", caption: "lo-fi beat", turns: ["a", "b", "c", "d"], bpm: [70, 92],
                             moods: ["Dusty", "Sleepy"], things: ["Tea", "Lamp"])

    @Test func captionHasTwoDistinctTurns() {
        var rng = SplitMix64(seed: 7)
        for _ in 0..<50 {
            let cap = Composing.caption(caption: Self.genre.caption, turns: Self.genre.turns, rng: &rng)
            #expect(cap.hasPrefix("lo-fi beat, ") && cap.hasSuffix(", instrumental"))
            let turns = cap.dropFirst("lo-fi beat, ".count).dropLast(", instrumental".count).components(separatedBy: ", ")
            #expect(Set(turns).count == 2 && Set(turns).isSubset(of: Self.genre.turns))
            let bpm = Composing.bpm(Self.genre.bpm, rng: &rng)
            #expect((70...92).contains(bpm))
            let name = Composing.name(moods: Self.genre.moods, things: Self.genre.things, rng: &rng)
            #expect(Self.genre.moods.contains { m in Self.genre.things.contains { "\(m) \($0)" == name } })
        }
    }

    @Test(arguments: [([String](), "c, instrumental"), (["x"], "c, x, instrumental"), (["a", "a"], "c, a, instrumental")])
    func captionWithFewTurns(turns: [String], want: String) {
        var rng = SplitMix64(seed: 1)
        #expect(Composing.caption(caption: "c", turns: turns, rng: &rng) == want)
    }
}

@Suite struct GenresFileTests {
    static let repoGenres: String = {
        let url = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Resources/genres.json")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }()

    static func doc(_ genres: String) -> String { #"{"genres": ["# + genres + "]}" }
    static let good = #"{"id": "jazz", "name": "Jazz", "caption": "a trio", "turns": ["brushes"], "bpm": [90, 140]}"#

    @Test func theRepositorysFileHasNineGenres() throws {
        let parsed = try GenresFile.parse(Self.repoGenres)
        #expect(parsed.genres.count == 9)
        #expect(parsed.skipped.isEmpty)
    }

    @Test func theRepositorysFileRoundTripsByteForByte() throws {
        #expect(GenresFile.format(try JSONValue.parse(Self.repoGenres)) == Self.repoGenres)
    }

    @Test func unknownKeysRawUTF8AndTopLevelKeysAreKept() throws {
        let doc: JSONValue = .object([
            ("genres", .array([.object([("id", .string("x")), ("name", .string("Café")),
                                        ("x-note", .object([("a", .array([.int(1), .int(2)]))])), ("turns", .array([]))])])),
            ("comment", .string("kept")),
        ])
        #expect(GenresFile.format(doc) == "{\n  \"genres\": [\n    {\n      \"id\": \"x\",\n      \"name\": \"Café\",\n      \"x-note\": {\"a\": [1, 2]},\n      \"turns\": []\n    }\n  ],\n  \"comment\": \"kept\"\n}\n")
    }

    @Test func escapes() {
        #expect(JSONValue.string("a\"b\\c\n\u{1}é\u{7F}").dumps() == #""a\"b\\c\n\u0001é"# + "\u{7F}\"")
        #expect(JSONValue.double(90).dumps() == "90.0")
    }

    @Test func missingWordsFallBackToTheSharedLists() throws {
        let g = try #require(try GenresFile.parse(Self.doc(Self.good)).genres.first)
        #expect(g.moods == Rules.defaultMoods && g.things == Rules.defaultThings)
        #expect(g.turns == ["brushes"] && g.bpm == [90, 140])
    }

    @Test(arguments: [
        ("{", "not valid JSON"),
        ("[]", #"needs a non-empty "genres" list"#),
        (#"{"genres": []}"#, #"needs a non-empty "genres" list"#),
        (doc("3"), "genre 1 is not an object"),
        (doc(#"{"id": "Jazz"}"#), "genre 1: id missing, repeated or not lower-case letters, digits and dashes"),
        (doc(#"{"id": "-jazz"}"#), "genre 1: id missing, repeated or not lower-case letters, digits and dashes"),
        (doc(good + "," + good), "genre 2: id missing, repeated or not lower-case letters, digits and dashes"),
        (doc(#"{"id": "a", "name": "A/B"}"#), "genre 1: name missing, repeated, or usable as no folder name"),
        (doc(#"{"id": "a", "name": ".a"}"#), "genre 1: name missing, repeated, or usable as no folder name"),
        (doc(#"{"id": "a", "name": "  "}"#), "genre 1: name missing, repeated, or usable as no folder name"),
        (doc(#"{"id": "a", "name": "a\u0007"}"#), "genre 1: name missing, repeated, or usable as no folder name"),
        (doc(good + #", {"id": "b", "name": "Jazz"}"#), "genre 2: name missing, repeated, or usable as no folder name"),
        (doc(#"{"id": "a", "name": "A", "caption": " "}"#), "genre 1: caption missing"),
        (doc(#"{"id": "a", "name": "A", "caption": "c"}"#), "genre 1: turns must be a list of texts"),
        (doc(#"{"id": "a", "name": "A", "caption": "c", "turns": [1]}"#), "genre 1: turns must be a list of texts"),
        (doc(#"{"id": "a", "name": "A", "caption": "c", "turns": [], "moods": []}"#), "genre 1: moods must be a list of texts, not empty"),
        (doc(#"{"id": "a", "name": "A", "caption": "c", "turns": [], "things": [" "]}"#), "genre 1: things must be a list of texts, not empty"),
        (doc(#"{"id": "a", "name": "A", "caption": "c", "turns": [], "bpm": [90]}"#), "genre 1: bpm must be [low, high] between 30 and 300"),
        (doc(#"{"id": "a", "name": "A", "caption": "c", "turns": [], "bpm": [91, 90]}"#), "genre 1: bpm must be [low, high] between 30 and 300"),
        (doc(#"{"id": "a", "name": "A", "caption": "c", "turns": [], "bpm": [29, 90]}"#), "genre 1: bpm must be [low, high] between 30 and 300"),
        (doc(#"{"id": "a", "name": "A", "caption": "c", "turns": [], "bpm": [90.0, 100]}"#), "genre 1: bpm must be [low, high] between 30 and 300"),
    ])
    func mistakes(_ text: String, _ reason: String) {
        #expect(throws: GenresFile.Mistake(reason)) { try GenresFile.parse(text) }
    }

    @Test func aGenreNamedExportsIsSkippedTheRestLoad() throws {
        let p = try GenresFile.parse(Self.doc(Self.good + #", {"id": "x", "name": "exports"}"#))
        #expect(p.genres.map(\.name) == ["Jazz"])
        #expect(p.skipped == ["exports"])
    }

    @Test func editedFieldsAreTrimmed() {
        let e = GenresFile.edited(GenreFields(name: "  Bebop ", caption: " fast \n", turns: [" a", "", "  ", "a ", "b"], bpm: [90, 140]))
        #expect(e == GenreFields(name: "Bebop", caption: "fast", turns: ["a", "b"], bpm: [90, 140]))
    }

    @Test func aGenreKeepsItsOwnNameInAnyCase() {
        #expect(GenresFile.fieldError(GenreFields(name: "JAZZ", caption: "c", turns: [], bpm: [90, 100]), others: ["Lo-fi"]) == nil)
        #expect(GenresFile.fieldError(GenreFields(name: "jazz", caption: "c", turns: [], bpm: [90, 100]), others: ["Jazz"])
            == Refusal(field: .name, text: "There is already a genre called Jazz."))
    }

    @Test func lineNumbersCountTheLinesAsSent() {
        let long = String(repeating: "t", count: 121)
        #expect(GenresFile.fieldError(GenreFields(name: "N", caption: "c", turns: ["", long], bpm: [90, 100]), others: [])
            == Refusal(field: .turns, text: "Line 2 is longer than 120 characters."))
    }

    @Test(arguments: [
        ("Hard Bop!", Set<String>(), "hard-bop"),
        ("Café Crème", Set<String>(), "cafe-creme"),
        ("Jazz", Set(["jazz", "jazz-2"]), "jazz-3"),
        ("!!!", Set<String>(), "genre"),
        ("--x--", Set<String>(), "x"),
        ("日本", Set<String>(), "genre"),
        ("Ö", Set<String>(), "o"),
    ] as [(String, Set<String>, String)])
    func newIDs(name: String, taken: Set<String>, want: String) {
        let id = GenresFile.newID(for: name, taken: taken)
        #expect(id == want)
        #expect(GenresFile.isGenreID(id))
    }

    @Test func updatingKeepsOtherKeysInPlace() throws {
        let doc = try JSONValue.parse(#"{"genres": [{"id": "j", "x": 1, "name": "J", "caption": "c", "turns": [], "bpm": [90, 100], "moods": ["M"]}]}"#)
        let new = GenresFile.updating(doc, id: "j", with: GenreFields(name: "K", caption: "d", turns: ["t"], bpm: [80, 90]))
        #expect(new.dumps() == #"{"genres": [{"id": "j", "x": 1, "name": "K", "caption": "d", "turns": ["t"], "bpm": [80, 90], "moods": ["M"]}]}"#)
        #expect(GenresFile.removing(new, id: "j").dumps() == #"{"genres": []}"#)
    }
}
