/// Which music model is suggested and which is chosen.
public enum ModelRules {
    /// The suggested model's index in a list running smallest first: the
    /// last whose `from` is at most `memory`, or the first when none is.
    public static func suggested(from: [Int64], memory: Int64) -> Int {
        from.lastIndex { $0 <= memory } ?? 0
    }

    /// The chosen model's index. `saved` when the list has it and it is on
    /// disk, or when no model is; otherwise the last on disk, the largest;
    /// with none on disk and nothing saved, `suggested`.
    public static func chosen(saved: String?, ids: [String], onDisk: [Bool], suggested: Int) -> Int {
        let s = saved.flatMap { ids.firstIndex(of: $0) }
        guard let last = onDisk.lastIndex(of: true) else { return s ?? suggested }
        if let s, onDisk[s] { return s }
        return last
    }
}
