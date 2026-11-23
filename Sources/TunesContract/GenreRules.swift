/// The genre validation shared by the engine and the panel.
public enum GenreRules {
    /// The first rule the fields break, in the panel's order, or nil.
    /// `others` are the names of the other genres, for the duplicate rule.
    public static func fieldError(_ fields: GenreFieldsText, others: [String]) -> Refusal? {
        nil
    }
}

/// The fields as typed: tempos are text until they parse.
public struct GenreFieldsText: Sendable, Equatable {
    public var name: String
    public var caption: String
    /// One per line.
    public var turns: String
    public var slowest: String
    public var fastest: String

    public init(name: String, caption: String, turns: String, slowest: String, fastest: String) {
        self.name = name
        self.caption = caption
        self.turns = turns
        self.slowest = slowest
        self.fastest = fastest
    }
}
