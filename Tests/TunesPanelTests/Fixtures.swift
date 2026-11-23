import Foundation
import Testing
import TunesContract
@testable import TunesPanel

/// The base time the fixtures are read at. A time written "@-N" or "@+N" in
/// a fixture is N seconds before or after it.
let NOW = 1_795_390_000.0
let HOME = "/Users/someone"

enum Fixture {
    /// The lines of `name`.jsonl with their times resolved.
    static func lines(_ name: String, base: Double = NOW) throws -> [Data] {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures"))
        let text = try String(contentsOf: url, encoding: .utf8)
        let times = try Regex(#""@([+-]\d+(?:\.\d+)?)""#)
        return text.split(separator: "\n").filter { !$0.allSatisfy(\.isWhitespace) }.map { line in
            let resolved = String(line).replacing(times) { m in
                let offset = Double(String(m.output[1].substring!))!
                return String(base + offset)
            }
            return Data(resolved.utf8)
        }
    }

    /// Every snapshot in `name`, in order.
    static func snapshots(_ name: String) throws -> [Snapshot] {
        try lines(name).map { try JSONDecoder().decode(Snapshot.self, from: $0) }
    }

    /// The last snapshot in `name`.
    static func load(_ name: String) throws -> Snapshot {
        try #require(snapshots(name).last)
    }

    static var all: [String] {
        let dir = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return files.filter { $0.hasSuffix(".jsonl") }.map { String($0.dropLast(6)) }.sorted()
    }

    /// The fixtures that are snapshots, not engine answers.
    static var states: [String] {
        all.filter { !["26-genre-jazz", "27-genre-results", "35-share-lines"].contains($0) }
    }

    static func json(_ name: String) throws -> [[String: Any]] {
        try lines(name).map { try #require(JSONSerialization.jsonObject(with: $0) as? [String: Any]) }
    }
}

func card(_ s: Snapshot, _ p: Panel = Panel(), now: Double = NOW) -> Card {
    Decide.card(s, p, now: now, home: HOME)
}

func player(_ s: Snapshot, _ p: Panel = Panel(), now: Double = NOW) throws -> PlayerCard {
    guard case .player(let c) = card(s, p, now: now) else {
        Issue.record("not the player: \(card(s, p, now: now))")
        throw CancellationError()
    }
    return c
}

func chooser(_ s: Snapshot, _ p: Panel = Panel().openingChooser()) throws -> ChooserCard {
    guard case .chooser(let c) = card(s, p) else {
        Issue.record("not the chooser")
        throw CancellationError()
    }
    return c
}

func editor(_ s: Snapshot, _ p: Panel) throws -> EditorCard {
    guard case .editor(let c) = card(s, p) else {
        Issue.record("not the editor")
        throw CancellationError()
    }
    return c
}

func share(_ s: Snapshot, _ p: Panel) throws -> ShareCard {
    guard case .share(let c) = card(s, p) else {
        Issue.record("not the share sheet")
        throw CancellationError()
    }
    return c
}

func setup(_ s: Snapshot) throws -> SetupCard {
    guard case .setup(let c) = card(s) else {
        Issue.record("not a setup card")
        throw CancellationError()
    }
    return c
}

/// Rows as [number, name, sub, right].
func rows(_ p: PlayerCard) -> [[String]] {
    p.next.rows.map { [$0.number, $0.name, $0.sub, $0.right] }
}

/// The composer's lines as read, with the right-hand text after " | ".
func lines(_ p: PlayerCard) -> [String] {
    p.composer.lines.map { $0.text + ($0.right.isEmpty ? "" : " | \($0.right)") }
}

@Suite("Fixtures")
struct FixtureTests {
    @Test("every snapshot fixture decodes into the contract", arguments: Fixture.states)
    func decodes(_ name: String) throws {
        let all = try Fixture.snapshots(name)
        #expect(!all.isEmpty)
        #expect(all.allSatisfy { $0.version == 1 })
    }

    @Test("a fixture names no other program", arguments: Fixture.all)
    func neutral(_ name: String) throws {
        let text = try Fixture.lines(name).map { String(decoding: $0, as: UTF8.self) }.joined().lowercased()
        for word in ["vulkan", "radeon", "mpv", "hypr", "linux", "/home/", ".mp3", "ffmpeg", "quickshell", "wayland", "game"] {
            #expect(!text.contains(word), "\(name) says \(word)")
        }
    }

    @Test("an unknown model state does not decode")
    func unknownEnum() throws {
        var line = try #require(String(data: Fixture.lines("05-queue-full")[0], encoding: .utf8))
        line = line.replacingOccurrences(of: "\"state\": \"idle\"", with: "\"state\": \"held_game\"")
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Snapshot.self, from: Data(line.utf8)) }
    }
}
