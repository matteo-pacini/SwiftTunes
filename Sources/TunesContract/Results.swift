import Foundation

/// A genre's fields. Sent to `saveGenre` untrimmed.
public struct GenreFields: Sendable, Equatable {
    public var name: String
    public var caption: String
    public var turns: [String]
    /// Exactly two: slowest, fastest.
    public var bpm: [Int]

    public init(name: String, caption: String, turns: [String], bpm: [Int]) {
        self.name = name
        self.caption = caption
        self.turns = turns
        self.bpm = bpm
    }
}

public struct GenreSaved: Sendable, Equatable {
    public var id: String
    /// Set when the genre's folder moved.
    public var renamed: Renamed?

    public init(id: String, renamed: Renamed?) {
        self.id = id
        self.renamed = renamed
    }
}

/// The genre names before and after a rename.
public struct Renamed: Sendable, Equatable {
    public var from: String
    public var to: String

    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }
}

public enum GenreField: String, Sendable, Equatable {
    case name, caption, turns, bpm
}

/// Why the engine (or the panel's local validation) declined. `text` is a
/// full sentence, plain.
public struct Refusal: Error, Sendable, Equatable {
    /// nil when the refusal names no field.
    public var field: GenreField?
    public var text: String

    public init(field: GenreField?, text: String) {
        self.field = field
        self.text = text
    }
}

public struct ShareInfo: Sendable, Equatable {
    public var name: String
    /// The folder's name.
    public var genre: String
    public var bpm: Int?
    public var key: String?
    public var length: Double?
    public var bytes: Int64
    /// The file.
    public var path: URL
    /// Where an export would go.
    public var exportPath: URL
    public var pinned: Bool

    public init(name: String, genre: String, bpm: Int?, key: String?, length: Double?, bytes: Int64, path: URL, exportPath: URL, pinned: Bool) {
        self.name = name
        self.genre = genre
        self.bpm = bpm
        self.key = key
        self.length = length
        self.bytes = bytes
        self.path = path
        self.exportPath = exportPath
        self.pinned = pinned
    }
}

public struct PinResult: Sendable, Equatable {
    public var on: Bool
    public var name: String

    public init(on: Bool, name: String) {
        self.on = on
        self.name = name
    }
}
