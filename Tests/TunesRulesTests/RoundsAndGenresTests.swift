import Foundation
import Testing
import TunesContract
@testable import TunesRules

private let K = (1...6).map { "2026010\($0)-000000-90bpm-C-major.m4a" }

@Suite struct RoundTests {
    @Test func theOrderMadeGoesRoundFromTheAnchor() {
        #expect(Rounds.made(K.reversed(), after: nil) == K)
        #expect(Rounds.made(K, after: K[2]) == Array(K[3...]) + Array(K[...2]))
        // An anchor whose file is gone still places the order.
        #expect(Rounds.made(Array(K[..<2]) + Array(K[3...]), after: K[2]) == Array(K[3...]) + Array(K[..<2]))
    }

    @Test(arguments: [1, 2, 3, 5, 8, 13] as [UInt64])
    func aShuffledDrawHoldsEachTuneOnce(seed: UInt64) {
        var rng = SplitMix64(seed: seed)
        let order = Rounds.draw(K, shuffle: true, anchor: nil, avoid: nil, rng: &rng)
        #expect(order.sorted() == K)
    }

    @Test func shuffledDrawsDiffer() {
        var rng = SplitMix64(seed: 4)
        let draws = Set((0..<10).map { _ in Rounds.draw(K, shuffle: true, anchor: nil, avoid: nil, rng: &rng).joined() })
        #expect(draws.count > 1)
    }

    @Test(arguments: [true, false])
    func aDrawNeverStartsWithTheTuneToAvoid(shuffle: Bool) {
        var rng = SplitMix64(seed: 9)
        for _ in 0..<200 {
            for avoid in K {
                let order = Rounds.draw(K, shuffle: shuffle, anchor: avoid, avoid: avoid, rng: &rng)
                #expect(order.first != avoid && order.sorted() == K)
            }
        }
    }

    @Test func aSingleTuneIsDrawnEvenIfItIsTheOneToAvoid() {
        var rng = SplitMix64(seed: 1)
        #expect(Rounds.draw([K[0]], shuffle: true, anchor: nil, avoid: K[0], rng: &rng) == [K[0]])
        #expect(Rounds.draw([], shuffle: true, anchor: nil, avoid: nil, rng: &rng).isEmpty)
    }

    @Test func shuffleOffIsTheOrderMadeFromTheAnchor() {
        var rng = SplitMix64(seed: 1)
        #expect(Rounds.draw([K[5], K[1], K[3]], shuffle: false, anchor: K[2], avoid: nil, rng: &rng) == [K[3], K[5], K[1]])
    }

    @Test func reconciledDropsTheGoneAndAddsTheNewAtTheEnd() {
        let order = [K[3], K[0], K[5]]
        // K[5] is gone; K[1] and K[4] are new; K[2] played this round.
        let kept = [K[0], K[1], K[2], K[3], K[4]]
        #expect(Rounds.reconciled(order, kept: kept, excluded: [K[2]]) == [K[3], K[0], K[1], K[4]])
        #expect(Rounds.reconciled([], kept: [], excluded: []) == [])
    }
}

@Suite struct ComposingTests {
    static let genre = Genre(id: "lofi", name: "Lo-fi", caption: "lo-fi beat", turns: ["a", "b", "c", "d"], bpm: [70, 92],
                             moods: ["Dusty", "Sleepy"], things: ["Tea", "Lamp"])

    @Test func captionHasTwoDistinctTurns() {
        var rng = SplitMix64(seed: 7)
        for _ in 0..<50 {
            let cap = Composing.caption(caption: Self.genre.caption, turns: Self.genre.turns, sung: false, rng: &rng)
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
        #expect(Composing.caption(caption: "c", turns: turns, sung: false, rng: &rng) == want)
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

    @Test func theRepositorysGenresHaveTheirPalettes() throws {
        let genres = try GenresFile.parse(Self.repoGenres).genres
        #expect(genres.allSatisfy { $0.palette?.count == 4 && GenresFile.isPalette($0.palette) })
        #expect(genres.first { $0.id == "lofi" }?.palette == ["#241a2c", "#c97b8f", "#d9a15e", "#5d4a9c"])
        #expect(genres.first { $0.id == "acoustic" }?.palette == ["#1d1610", "#b5793f", "#5c8a4a", "#7a4a26"])
    }

    @Test func paletteIsOptional() throws {
        let none = try #require(try GenresFile.parse(Self.doc(Self.good)).genres.first)
        #expect(none.palette == nil && none.fields.palette == nil)
        let null = try GenresFile.parse(Self.doc(#"{"id": "a", "name": "A", "caption": "c", "turns": [], "bpm": [90, 100], "palette": null}"#))
        #expect(null.genres.first?.palette == nil)
        let upper = try GenresFile.parse(Self.doc(##"{"id": "a", "name": "A", "caption": "c", "turns": [], "bpm": [90, 100], "palette": ["#ABCDEF", "#abcdef", "#012345", "#6789aB"]}"##))
        #expect(upper.genres.first?.palette == ["#ABCDEF", "#abcdef", "#012345", "#6789aB"])
    }

    @Test(arguments: [
        (nil, true), (["#000000", "#111111", "#222222", "#333333"], true),
        (["#000000", "#111111", "#222222"], false), (["#000000", "#111111", "#222222", "#333333", "#444444"], false),
        (["#000000", "#111111", "#222222", "#33333"], false), (["#000000", "#111111", "#222222", "red"], false),
        ([String](), false),
    ] as [([String]?, Bool)])
    func palettesASaveMayCarry(_ palette: [String]?, _ ok: Bool) {
        #expect(GenresFile.isPalette(palette) == ok)
    }

    @Test func aPaletteIsWrittenAfterBpmAndDroppedWhenNil() throws {
        let doc = try JSONValue.parse(#"{"genres": [{"id": "j", "name": "J", "caption": "c", "turns": [], "bpm": [90, 100], "moods": ["M"]}]}"#)
        let p = ["#000000", "#111111", "#222222", "#333333"]
        let added = GenresFile.updating(doc, id: "j", with: GenreFields(name: "J", caption: "c", turns: [], bpm: [90, 100], palette: p))
        #expect(added.dumps() == ##"{"genres": [{"id": "j", "name": "J", "caption": "c", "turns": [], "bpm": [90, 100], "palette": ["#000000", "#111111", "#222222", "#333333"], "moods": ["M"]}]}"##)
        let changed = GenresFile.updating(added, id: "j", with: GenreFields(name: "J", caption: "c", turns: [], bpm: [90, 100], palette: ["#ffffff"] + p.dropFirst()))
        #expect(changed.dumps().contains(##""bpm": [90, 100], "palette": ["#ffffff", "#111111""##))
        let dropped = GenresFile.updating(added, id: "j", with: GenreFields(name: "J", caption: "c", turns: [], bpm: [90, 100], palette: nil))
        #expect(dropped == doc)
        #expect(GenresFile.object(id: "n", GenreFields(name: "N", caption: "c", turns: [], bpm: [90, 100], palette: p)).dumps()
            == ##"{"id": "n", "name": "N", "caption": "c", "turns": [], "bpm": [90, 100], "palette": ["#000000", "#111111", "#222222", "#333333"]}"##)
        #expect(GenresFile.object(id: "n", GenreFields(name: "N", caption: "c", turns: [], bpm: [90, 100])).dumps().contains("palette") == false)
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
        (doc(good + #", {"id": "b", "name": "jAZZ"}"#), "genre 2: name missing, repeated, or usable as no folder name"),
        (doc(#"{"id": "a", "name": "A", "caption": " "}"#), "genre 1: caption missing"),
        (doc(#"{"id": "a", "name": "A", "caption": "c"}"#), "genre 1: turns must be a list of texts"),
        (doc(#"{"id": "a", "name": "A", "caption": "c", "turns": [1]}"#), "genre 1: turns must be a list of texts"),
        (doc(#"{"id": "a", "name": "A", "caption": "c", "turns": [], "moods": []}"#), "genre 1: moods must be a list of texts, not empty"),
        (doc(#"{"id": "a", "name": "A", "caption": "c", "turns": [], "things": [" "]}"#), "genre 1: things must be a list of texts, not empty"),
        (doc(#"{"id": "a", "name": "A", "caption": "c", "turns": [], "bpm": [90]}"#), "genre 1: bpm must be [low, high] between 30 and 300"),
        (doc(#"{"id": "a", "name": "A", "caption": "c", "turns": [], "bpm": [91, 90]}"#), "genre 1: bpm must be [low, high] between 30 and 300"),
        (doc(#"{"id": "a", "name": "A", "caption": "c", "turns": [], "bpm": [29, 90]}"#), "genre 1: bpm must be [low, high] between 30 and 300"),
        (doc(#"{"id": "a", "name": "A", "caption": "c", "turns": [], "bpm": [90.0, 100]}"#), "genre 1: bpm must be [low, high] between 30 and 300"),
        (doc(##"{"id": "a", "name": "A", "caption": "c", "turns": [], "bpm": [90, 100], "palette": ["#000000", "#111111", "#222222"]}"##), "genre 1: palette must be four colours as #RRGGBB"),
        (doc(##"{"id": "a", "name": "A", "caption": "c", "turns": [], "bpm": [90, 100], "palette": ["#000000", "#111111", "#222222", "#33333g"]}"##), "genre 1: palette must be four colours as #RRGGBB"),
        (doc(##"{"id": "a", "name": "A", "caption": "c", "turns": [], "bpm": [90, 100], "palette": ["#000000", "#111111", "#222222", "333333"]}"##), "genre 1: palette must be four colours as #RRGGBB"),
        (doc(##"{"id": "a", "name": "A", "caption": "c", "turns": [], "bpm": [90, 100], "palette": "#000000"}"##), "genre 1: palette must be four colours as #RRGGBB"),
        (doc(#"{"id": "a", "name": "A", "caption": "c", "turns": [], "bpm": [90, 100], "palette": [1, 2, 3, 4]}"#), "genre 1: palette must be four colours as #RRGGBB"),
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
