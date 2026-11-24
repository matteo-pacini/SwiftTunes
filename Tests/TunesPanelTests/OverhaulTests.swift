import Foundation
import Testing
import TunesContract
@testable import TunesPanel

/// The starting genres as the bundled genres file lists them, with the
/// palette each gives (nil until the file carries one).
enum StartingGenres {
    static func all() throws -> [(name: String, hex: [String]?)] {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Resources/genres.json")
        let data = try Data(contentsOf: file)
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let genres = try #require(root["genres"] as? [[String: Any]])
        return genres.compactMap { g in (g["name"] as? String).map { ($0, g["palette"] as? [String]) } }
    }
}

@Suite("Palettes")
struct PaletteTests {
    static let generated: [String] = (0..<200).map { "Genre \($0) \(["Dub", "Bossa", "Drone", "Chiptune", "Fado", "Gamelan", "Polka", "Grime"][$0 % 8])" }

    func readable(_ p: Palette) -> Bool {
        p.field(dark: true).allSatisfy { RGB.contrast(Palette.darkText, $0) >= 4.5 }
            && p.field(dark: false).allSatisfy { RGB.contrast(Palette.lightText, $0) >= 4.5 }
    }

    @Test("white text on the dark field and near-black on the light field reach 4.5:1 for every starting genre")
    func starting() throws {
        let genres = try StartingGenres.all()
        #expect(genres.count == 9)
        for g in genres {
            let p = Palette.of(name: g.name, hex: g.hex)
            #expect(p.colors.count == 4)
            #expect(readable(p), "\(g.name)")
        }
    }

    @Test("and for 200 made from names", arguments: generated)
    func madeFromNames(_ name: String) {
        #expect(readable(Palette.made(from: name)))
    }

    @Test("bright and pale given colours are still made readable", arguments: [
        ["#FFFFFF", "#FF3D9A", "#2BD4FF", "#FFFF00"], ["#000000", "#000000", "#101010", "#202020"], ["#170A2E", "#FF3D9A", "#2BD4FF", "#6A2BD9"],
    ])
    func extremes(_ hex: [String]) {
        #expect(readable(Palette.of(name: "x", hex: hex)))
    }

    @Test("the file's four colours are used as given; anything else falls back to the name's")
    func given() {
        let p = Palette.of(name: "Jazz", hex: ["#1a1230", "#B8562B", "#7a2848", "#23408f"])
        #expect(p.colors.map(\.hex) == ["#1A1230", "#B8562B", "#7A2848", "#23408F"])
        #expect(Palette.of(name: "Jazz", hex: ["#1a1230"]) == Palette.made(from: "Jazz"))
        #expect(Palette.of(name: "Jazz", hex: ["#1a1230", "red", "#7a2848", "#23408f"]) == Palette.made(from: "Jazz"))
        #expect(Palette.of(name: "Jazz", hex: nil) == Palette.made(from: "Jazz"))
    }

    @Test("a name always makes the same palette; different names differ")
    func deterministic() {
        #expect(Palette.made(from: "Bossa nova") == Palette.made(from: "Bossa nova"))
        #expect(Palette.made(from: "Bossa nova") != Palette.made(from: "Bossa Nova"))
        #expect(Set(Self.generated.map { Palette.made(from: $0).colors[1].hex }).count > 150)
    }

    @Test("hex round trip and the contrast formula's ends")
    func rgb() {
        #expect(RGB(hex: "#ff3d9a")?.hex == "#FF3D9A")
        #expect(RGB(hex: "ff3d9a")?.hex == "#FF3D9A")
        #expect(RGB(hex: "#ff3d9") == nil && RGB(hex: "#gggggg") == nil)
        #expect(abs(RGB.contrast(RGB(0, 0, 0), RGB(1, 1, 1)) - 21) < 1e-9)
        #expect(RGB.contrast(RGB(0.5, 0.5, 0.5), RGB(0.5, 0.5, 0.5)) == 1)
    }

    @Test("the player's backdrop is the selected genre's palette")
    func backdrop() throws {
        let s = try Fixture.load("05-queue-full")
        #expect(try player(s).palette == Palette.of(name: "Jazz", hex: s.genres[4].palette))
        #expect(s.genres[4].palette?.count == 4)
    }
}

@Suite("Artwork")
struct ArtworkTests {
    let palette = Palette.made(from: "Jazz")

    @Test("the same tune gives the same picture; another tune another")
    func deterministic() {
        let a = Artwork.recipe(name: "Lazy Avenue", bpm: 139, key: "C major", palette: palette)
        #expect(a == Artwork.recipe(name: "Lazy Avenue", bpm: 139, key: "C major", palette: palette))
        #expect(a != Artwork.recipe(name: "Lazy Avenue", bpm: 140, key: "C major", palette: palette))
        #expect(a != Artwork.recipe(name: "Lazy Avenue", bpm: 139, key: "C minor", palette: palette))
        #expect(a != Artwork.recipe(name: "Quiet Ledger", bpm: 139, key: "C major", palette: palette))
    }

    @Test("a 3 × 3 mesh with fixed corners and points inside, colours from the palette, 26 columns in 0…1",
          arguments: ["Lazy Avenue", "Brass Lantern", "20260105-100000-70bpm-G-major", "<i>Name</i>", ""])
    func shape(_ name: String) {
        let a = Artwork.recipe(name: name, bpm: nil, key: nil, palette: palette)
        #expect(a.points.count == 9 && a.indices.count == 9)
        #expect([a.points[0], a.points[2], a.points[6], a.points[8]] == [SIMD2(0, 0), SIMD2(1, 0), SIMD2(0, 1), SIMD2(1, 1)])
        #expect(a.points.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
        #expect(a.indices.allSatisfy { (0..<4).contains($0) })
        #expect(a.levels.count == Artwork.columns && a.levels.allSatisfy { (0...1).contains($0) })
        let field = palette.field(dark: true)
        #expect(a.colors(field).allSatisfy { field.contains($0) })
    }

    @Test("THIS ROUND's rows carry their tune's picture in the genre's palette")
    func inUpNext() throws {
        let s = try Fixture.load("05-queue-full")
        let p = try player(s)
        let t = try #require(s.tune)
        let expected = [Artwork.recipe(name: t.name, bpm: t.bpm, key: t.key, palette: Decide.palette(s))]
            + s.queue.prefix(2).map { Artwork.recipe(name: $0.name, bpm: $0.bpm, key: $0.key, palette: Decide.palette(s)) }
        #expect(p.next.rows.map(\.artwork) == expected)
    }
}

@Suite("Overhaul layout")
struct LayoutTests {
    @Test("the forming wave: stage only, bounded, rendering taller than writing, no growth over time")
    func forming() {
        let n = 78
        for t in stride(from: 0.0, through: 600, by: 7.3) {
            let w = (0..<n).map { Forming.level(column: $0, of: n, at: t, stage: .writing) }
            let r = (0..<n).map { Forming.level(column: $0, of: n, at: t, stage: .rendering) }
            #expect(w.allSatisfy { (0.06...1).contains($0) } && r.allSatisfy { (0.06...1).contains($0) })
            #expect(r.reduce(0, +) > w.reduce(0, +))
        }
        // The mean height at ten minutes is that at the start, within the wave's own sway.
        func mean(_ t: Double) -> Double { (0..<n).map { Forming.level(column: $0, of: n, at: t, stage: .writing) }.reduce(0, +) / Double(n) }
        #expect(abs(mean(600) - mean(0)) < 0.08)
    }

    @Test("the hero forms only with no tune and a job shown", arguments: [
        ("06-first-tune", JobStage?.some(.rendering)), ("10-writing", nil), ("05-queue-full", nil), ("08-nothing-kept", nil),
    ])
    func heroForming(_ name: String, _ stage: JobStage?) throws {
        #expect(try player(Fixture.load(name)).now.forming == stage)
    }

    @Test("the label carries the heading's suffix", arguments: [
        ("05-queue-full", "NOW PLAYING"), ("07-composer-off-kept", "NOW PLAYING · KEPT TUNES"), ("32-repeat-one", "NOW PLAYING · REPEATING"),
    ])
    func label(_ name: String, _ label: String) throws {
        #expect(try player(Fixture.load(name)).now.label == label)
    }

    @Test("the composer's pill: the state when not plain on, else the right-hand words", arguments: [
        ("05-queue-full", "resting, queue is full", Tone.green), ("06-first-tune", "using 3.9 GiB of memory", .dim),
        ("12-held-power", "held for low power", .orange), ("15-failed-playing", "failed", .red),
        ("08-nothing-kept", "off", .soft), ("20-session", "using 5.8 GiB of memory", .dim),
    ])
    func pill(_ name: String, _ text: String, _ tone: Tone) throws {
        let c = try player(Fixture.load(name)).composer
        #expect(c.pill == text && c.pillTone == tone)
    }

    @Test("the editor's Colours row: the genre's colours until one is picked")
    func colours() throws {
        let s = try Fixture.load("05-queue-full")
        let jazz = s.genres[4]
        let p = Panel().editingGenre(jazz).loaded(.success(GenreFields(name: "Jazz", caption: "c", turns: [], bpm: [80, 120])), id: "jazz", now: NOW)
        let e = try editor(s, p)
        #expect(e.coloursLabel == "Colours")
        #expect(e.colours == Palette.made(from: "Jazz").colors.map(\.hex))
        let picked = p.pickingColour(2, hex: "#123abc", shown: e.colours)
        var expected = e.colours
        expected[2] = "#123ABC"
        #expect(try editor(s, picked).colours == expected)
        #expect(p.pickingColour(4, hex: "#123abc", shown: e.colours) == p)
        #expect(p.pickingColour(0, hex: "blue", shown: e.colours) == p)
        let new = Panel().addingGenre().typed(.name, "Bossa nova")
        #expect(try editor(s, new).colours == Palette.made(from: "Bossa nova").colors.map(\.hex))
    }

    @Test("a genre's own palette: the backdrop, the editor's row after loading, and Save sends it")
    func ownPalette() throws {
        var s = try Fixture.load("05-queue-full")
        let hex = ["#1A1230", "#B8562B", "#7A2848", "#23408F"]
        s.genres[4].palette = hex
        #expect(try player(s).palette.colors.map(\.hex) == hex)
        let loaded = Panel().editingGenre(s.genres[4])
            .loaded(.success(GenreFields(name: "Jazz", caption: "c", turns: [], bpm: [80, 120], palette: hex)), id: "jazz", now: NOW)
        let e = try editor(s, loaded)
        #expect(e.colours == hex)
        guard case .send(_, _, let fields, _) = loaded.saving(s) else { Issue.record("not sent"); return }
        #expect(fields.palette == hex)
        let picked = loaded.pickingColour(0, hex: "#000000", shown: e.colours)
        guard case .send(_, _, let changed, _) = picked.saving(s) else { Issue.record("not sent"); return }
        #expect(changed.palette == ["#000000"] + hex.dropFirst())
        // A genre with no palette keeps none unless a colour is picked.
        let plain = Panel().editingGenre(s.genres[0])
            .loaded(.success(GenreFields(name: "Lo-fi", caption: "c", turns: [], bpm: [70, 92])), id: "lofi", now: NOW)
        guard case .send(_, _, let untouched, _) = plain.saving(s) else { Issue.record("not sent"); return }
        #expect(untouched.palette == nil)
    }
}
