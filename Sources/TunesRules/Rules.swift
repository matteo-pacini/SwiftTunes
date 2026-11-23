/// The engine's fixed numbers.
public enum Rules {
    /// The language model writes five audio codes a second.
    public static let codeHz = 5.0
    public static let waveBars = 78
    /// A final silent run at least this long is cut off.
    public static let tailMin = 1.0
    /// A silent run longer than this anywhere else means the plan is written again.
    public static let midMax = 5.0
    public static let fade = 1.5
    public static let quietDB = -50.0
    public static let quietMax = 5.0
    public static let levelWindow = 0.1
    /// Rate of the mono decode the backstop and the waveform read.
    public static let decodeRate = 8000.0
    public static let rewritesMax = 3
    public static let retryFirst = 3.0
    public static let retryAfter = 30.0
    public static let scrapHold = 10.0
    public static let timingsKept = 5
    public static let holdRunning = 10.0
    public static let holdWaiting = 30.0
    public static let poll = 0.5
    public static let startTimeout = 120.0
    public static let healthGap = 0.2
    /// Download progress reaches the snapshot at most this often.
    public static let downloadGap = 0.5
    /// Seconds the engine waits for the server to exit after a failed poll.
    public static let lostGrace = 2.0
    /// Kept tunes the queue shows with shuffle off.
    public static let keptShown = 3
    public static let gone = "That tune is no longer there."
    public static let genreGone = "That genre no longer exists."
    public static let ramBytes: Int64 = 8 * 1024 * 1024 * 1024
    public static let lyrics = "[Instrumental]"
    public static let tuneExtension = "m4a"
    public static let roleWords = ["lm": "language model", "dit": "diffusion model", "text": "text encoder", "vae": "VAE"]
    public static let defaultMoods = ["Quiet", "Golden", "Distant", "Gentle", "Bright", "Hidden", "Slow", "Silver", "Warm", "Late"]
    public static let defaultThings = ["Harbour", "Garden", "Window", "Letter", "River", "Station", "Lantern", "Meadow", "Bridge", "Island"]

    /// Seconds before the next try after `failures` failures in a row.
    public static func retryDelay(failures: Int) -> Double {
        failures <= 1 ? retryFirst : retryAfter
    }
}
