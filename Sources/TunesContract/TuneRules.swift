/// The tune-name validation shared by the engine and the panel.
public enum TuneRules {
    public static let nameMax = 60

    /// The first rule a tune's name breaks, or nil. Checked on the trimmed
    /// name, in this order, with these sentences:
    ///   `A tune needs a name.`
    ///   `A name cannot hold control characters or line breaks.`
    ///   `A name is at most 60 characters; this one has N.`
    /// Trimming and counting are the genre rules': Unicode whitespace off
    /// both ends, then Unicode scalars.
    public static func nameError(_ name: String) -> String? {
        let t = GenreRules.trim(name)
        if t.isEmpty { return "A tune needs a name." }
        if t.unicodeScalars.contains(where: GenreRules.isControl) {
            return "A name cannot hold control characters or line breaks."
        }
        let count = t.unicodeScalars.count
        if count > nameMax { return "A name is at most \(nameMax) characters; this one has \(count)." }
        return nil
    }
}
