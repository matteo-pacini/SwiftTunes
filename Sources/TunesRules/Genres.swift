import Foundation
import TunesContract

/// A genre as the genres file gives it.
public struct Genre: Equatable, Sendable {
    public var id: String
    public var name: String
    public var caption: String
    public var turns: [String]
    public var bpm: [Int]
    /// Words for tune names; the shared list when the file gives none.
    public var moods: [String]
    public var things: [String]
    /// Four colours as `#RRGGBB`, nil when the file gives none.
    public var palette: [String]?

    public init(id: String, name: String, caption: String, turns: [String], bpm: [Int], moods: [String] = Rules.defaultMoods,
                things: [String] = Rules.defaultThings, palette: [String]? = nil) {
        self.id = id
        self.name = name
        self.caption = caption
        self.turns = turns
        self.bpm = bpm
        self.moods = moods
        self.things = things
        self.palette = palette
    }

    /// The fields the editor shows, as stored.
    public var fields: GenreFields {
        GenreFields(name: name, caption: caption, turns: turns, bpm: bpm, palette: palette)
    }
}

public enum GenresFile {
    /// Why the file cannot be read; `description` is the reason as shown
    /// after "genres.json: ".
    public struct Mistake: Error, Equatable, CustomStringConvertible {
        public var description: String
        public init(_ description: String) { self.description = description }
    }

    /// The genres in file order, and the names of genres left out because
    /// they would take the Exports folder.
    public static func parse(_ text: String) throws(Mistake) -> (genres: [Genre], skipped: [String]) {
        guard let raw = try? JSONValue.parse(text) else { throw Mistake("not valid JSON") }
        guard case .array(let list)? = raw["genres"], !list.isEmpty, case .object = raw else {
            throw Mistake(#"needs a non-empty "genres" list"#)
        }
        var out: [Genre] = []
        var skipped: [String] = []
        var ids: Set<String> = []
        var names: Set<String> = []
        for (n, g) in list.enumerated() {
            let place = "genre \(n + 1)"
            guard case .object = g else { throw Mistake("\(place) is not an object") }
            guard case .string(let id)? = g["id"], isGenreID(id), !ids.contains(id) else {
                throw Mistake("\(place): id missing, repeated or not lower-case letters, digits and dashes")
            }
            guard case .string(let name)? = g["name"], !GenreRules.trim(name).isEmpty, !name.contains("/"),
                  !name.hasPrefix("."), !names.contains(name.lowercased()),
                  !name.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 })
            else {
                throw Mistake("\(place): name missing, repeated, or usable as no folder name")
            }
            if name.lowercased() == GenreRules.exports.lowercased() {
                skipped.append(name)
                continue
            }
            guard case .string(let caption)? = g["caption"], !GenreRules.trim(caption).isEmpty else {
                throw Mistake("\(place): caption missing")
            }
            func texts(_ key: String, fallback: [String]?) throws(Mistake) -> [String] {
                let value = g[key] ?? fallback.map { .array($0.map(JSONValue.string)) }
                var out: [String] = []
                if case .array(let items)? = value, fallback == nil || !items.isEmpty {
                    for item in items {
                        guard case .string(let s) = item, !GenreRules.trim(s).isEmpty else { out = []; break }
                        out.append(s)
                    }
                    if out.count == items.count { return out }
                }
                throw Mistake("\(place): \(key) must be a list of texts" + (fallback == nil ? "" : ", not empty"))
            }
            let turns = try texts("turns", fallback: nil)
            let moods = try texts("moods", fallback: Rules.defaultMoods)
            let things = try texts("things", fallback: Rules.defaultThings)
            guard case .array(let b)? = g["bpm"], b.count == 2, case .int(let lo) = b[0], case .int(let hi) = b[1],
                  GenreRules.bpmRange.lowerBound <= lo, lo <= hi, hi <= GenreRules.bpmRange.upperBound
            else {
                throw Mistake("\(place): bpm must be [low, high] between \(GenreRules.bpmRange.lowerBound) and \(GenreRules.bpmRange.upperBound)")
            }
            var palette: [String]?
            if let raw = g["palette"], raw != .null {
                guard case .array(let items) = raw, items.count == 4 else { throw Mistake("\(place): palette must be four colours as #RRGGBB") }
                var colours: [String] = []
                for item in items {
                    guard case .string(let c) = item, isColour(c) else { throw Mistake("\(place): palette must be four colours as #RRGGBB") }
                    colours.append(c)
                }
                palette = colours
            }
            ids.insert(id)
            // Without case, as the editor compares, and as a volume that
            // ignores case would give two such genres one folder.
            names.insert(name.lowercased())
            out.append(Genre(id: id, name: name, caption: caption, turns: turns, bpm: [lo, hi], moods: moods, things: things, palette: palette))
        }
        return (out, skipped)
    }

    /// `#` and six hex digits.
    public static func isColour(_ s: String) -> Bool {
        let u = Array(s.unicodeScalars)
        return u.count == 7 && u[0] == "#" && u.dropFirst().allSatisfy {
            ("0"..."9").contains($0) || ("a"..."f").contains($0) || ("A"..."F").contains($0)
        }
    }

    /// A palette a save may carry: none, or four colours.
    public static func isPalette(_ p: [String]?) -> Bool {
        guard let p else { return true }
        return p.count == 4 && p.allSatisfy(isColour)
    }

    public static let paletteRefusal = "A palette is four colours."

    /// Lower-case letters, digits and dashes, not starting with a dash.
    public static func isGenreID(_ id: String) -> Bool {
        guard let first = id.unicodeScalars.first, first != "-" else { return false }
        return id.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
    }

    /// The file's text for `doc`: two-space indents, a genre's turns one per
    /// line, every other value on its key's line; keys keep their order and
    /// unknown ones are kept.
    public static func format(_ doc: JSONValue) -> String {
        guard case .object(let top) = doc else { return doc.dumps() + "\n" }
        func value(_ key: String, _ v: JSONValue) -> String {
            if key == "turns", case .array(let items) = v, !items.isEmpty {
                return "[\n" + items.map { "        " + $0.dumps() }.joined(separator: ",\n") + "\n      ]"
            }
            return v.dumps()
        }
        func genre(_ g: JSONValue) -> String {
            guard case .object(let fields) = g else { return "    " + g.dumps() }
            return "    {\n" + fields.map { "      \(JSONValue.string($0.key).dumps()): \(value($0.key, $0.value))" }
                .joined(separator: ",\n") + "\n    }"
        }
        let lines = top.map { field -> String in
            if field.key == "genres", case .array(let gs) = field.value {
                return "  \"genres\": [\n" + gs.map(genre).joined(separator: ",\n") + "\n  ]"
            }
            return "  \(JSONValue.string(field.key).dumps()): \(field.value.dumps())"
        }
        return "{\n" + lines.joined(separator: ",\n") + "\n}\n"
    }

    /// The editor's fields as saved: name and caption trimmed, turns trimmed
    /// with blank and repeated ones dropped, bpm as sent.
    public static func edited(_ fields: GenreFields) -> GenreFields {
        var turns: [String] = []
        for t in fields.turns {
            let s = GenreRules.trim(t)
            if !s.isEmpty && !turns.contains(s) { turns.append(s) }
        }
        return GenreFields(name: GenreRules.trim(fields.name), caption: GenreRules.trim(fields.caption), turns: turns, bpm: fields.bpm,
                           palette: fields.palette)
    }

    /// The first rule the fields break, through the shared rules. Pass the
    /// fields as sent, so "Line N" counts the lines as typed.
    public static func fieldError(_ fields: GenreFields, others: [String]) -> Refusal? {
        guard fields.bpm.count == 2 else {
            return Refusal(field: .bpm, text: "The slowest tempo needs a whole number.")
        }
        let text = GenreFieldsText(
            name: fields.name, caption: fields.caption, turns: fields.turns.joined(separator: "\n"),
            slowest: String(fields.bpm[0]), fastest: String(fields.bpm[1])
        )
        return GenreRules.fieldError(text, others: others)
    }

    /// A free genre id for `name`: lower-case ASCII letters, digits and
    /// dashes, accents dropped; "genre" when nothing is left; "-2", "-3"…
    /// while taken.
    public static func newID(for name: String, taken: Set<String>) -> String {
        let ascii = String(String.UnicodeScalarView(name.decomposedStringWithCompatibilityMapping.unicodeScalars.filter { $0.isASCII }))
        var base = ""
        var dash = false
        for u in ascii.lowercased().unicodeScalars {
            if ("a"..."z").contains(u) || ("0"..."9").contains(u) {
                if dash && !base.isEmpty { base += "-" }
                dash = false
                base.unicodeScalars.append(u)
            } else {
                dash = true
            }
        }
        if base.isEmpty { base = "genre" }
        var id = base
        var n = 2
        while taken.contains(id) {
            id = "\(base)-\(n)"
            n += 1
        }
        return id
    }

    /// A genre's fields as stored in the file.
    public static func object(id: String, _ fields: GenreFields) -> JSONValue {
        var f: [(key: String, value: JSONValue)] = [
            ("id", .string(id)),
            ("name", .string(fields.name)),
            ("caption", .string(fields.caption)),
            ("turns", .array(fields.turns.map(JSONValue.string))),
            ("bpm", .array(fields.bpm.map(JSONValue.int))),
        ]
        if let p = fields.palette { f.append(("palette", .array(p.map(JSONValue.string)))) }
        return .object(f)
    }

    /// `doc`'s genre `id` with the editor's fields written over its own,
    /// other keys kept in place.
    public static func updating(_ doc: JSONValue, id: String, with fields: GenreFields) -> JSONValue {
        guard case .object(var top) = doc, let at = top.firstIndex(where: { $0.key == "genres" }),
              case .array(var gs) = top[at].value else { return doc }
        for (n, g) in gs.enumerated() {
            guard case .object(var f) = g, g["id"] == .string(id) else { continue }
            let new: [(String, JSONValue)] = [
                ("name", .string(fields.name)), ("caption", .string(fields.caption)),
                ("turns", .array(fields.turns.map(JSONValue.string))), ("bpm", .array(fields.bpm.map(JSONValue.int))),
            ]
            for (k, v) in new {
                if let i = f.firstIndex(where: { $0.key == k }) { f[i].value = v } else { f.append((k, v)) }
            }
            if let p = fields.palette {
                let v = JSONValue.array(p.map(JSONValue.string))
                if let i = f.firstIndex(where: { $0.key == "palette" }) {
                    f[i].value = v
                } else {
                    // A new palette goes right after bpm, where the file keeps it.
                    let at = (f.firstIndex(where: { $0.key == "bpm" }) ?? (f.count - 1)) + 1
                    f.insert(("palette", v), at: at)
                }
            } else {
                f.removeAll { $0.key == "palette" }
            }
            gs[n] = .object(f)
        }
        top[at].value = .array(gs)
        return .object(top)
    }

    /// `doc` with genre `id` appended, or removed.
    public static func appending(_ doc: JSONValue, _ genre: JSONValue) -> JSONValue {
        mapGenres(doc) { $0 + [genre] }
    }

    public static func removing(_ doc: JSONValue, id: String) -> JSONValue {
        mapGenres(doc) { $0.filter { $0["id"] != .string(id) } }
    }

    private static func mapGenres(_ doc: JSONValue, _ f: ([JSONValue]) -> [JSONValue]) -> JSONValue {
        guard case .object(var top) = doc, let at = top.firstIndex(where: { $0.key == "genres" }),
              case .array(let gs) = top[at].value else { return doc }
        top[at].value = .array(f(gs))
        return .object(top)
    }
}
