/// What the server's log says.
public enum ServerLog {
    /// The device the server is started on.
    public static let device = "MTL0"
    static let listening = "[Server] Listening on"
    static let gpuName = "ggml_metal_device_init: GPU name:"
    static let started = "tunes-lifeline: started "

    /// The chip's name from a line `ggml_metal_device_init: GPU name:   MTL0 (Apple M4 Pro)`.
    public static func metalDevice(_ line: String) -> String? {
        guard line.hasPrefix(gpuName) else { return nil }
        let rest = line.dropFirst(gpuName.count).trimmingCharacters(in: .whitespaces)
        guard rest.hasPrefix(device) else { return nil }
        let after = rest.dropFirst(device.count).trimmingCharacters(in: .whitespaces)
        if after.hasPrefix("("), after.hasSuffix(")") {
            let name = after.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { return name }
        }
        return device
    }

    public static func isListening(_ line: String) -> Bool { line.hasPrefix(listening) }

    /// The server's pid from the lifeline's own line.
    public static func serverPID(_ line: String) -> Int32? {
        guard line.hasPrefix(started) else { return nil }
        return Int32(line.dropFirst(started.count).trimmingCharacters(in: .whitespaces))
    }

    /// The no_device detail: what the server offered instead, when its log
    /// says so (`--device MTL0 not found. Available: BLAS CPU`).
    public static func missingDevice(_ lines: [String]) -> String {
        let marker = "--device \(device) not found. Available:"
        for line in lines.reversed() {
            if let r = line.range(of: marker) {
                let offered = line[r.upperBound...].trimmingCharacters(in: .whitespaces)
                if !offered.isEmpty { return "the server offers only \(offered)" }
            }
        }
        return "the server listed no \(device)"
    }

    /// Whether the log names the missing device, so the exit is no_device.
    public static func saysNoDevice(_ lines: [String]) -> Bool {
        lines.contains { $0.contains("--device \(device) not found") }
    }

    /// The last line that reads as an error, trimmed.
    public static func lastError(_ lines: [String]) -> String? {
        let words = ["error", "fatal", "failed", "lost", "abort"]
        for line in lines.reversed() {
            let lower = line.lowercased()
            if words.contains(where: { lower.contains($0) }) {
                return line.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    /// The failure text for an exit nobody asked for.
    public static func exited(status: Int32, lines: [String]) -> String {
        "the model server exited (status \(status))" + (lastError(lines).map { ": \($0)" } ?? "")
    }
}
