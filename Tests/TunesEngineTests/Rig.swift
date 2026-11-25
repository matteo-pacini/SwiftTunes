import AVFoundation
import CryptoKit
import Foundation
import Testing
import TunesContract
@testable import TunesEngine
import TunesFakes
import TunesRules

/// Time that moves only when the rig moves it, to the next timer.
final class ManualClock: EngineClock {
    final class Timer: EngineTimer {
        let due: Double
        let seq: Int
        let fire: @MainActor () -> Void
        var cancelled = false

        init(due: Double, seq: Int, fire: @escaping @MainActor () -> Void) {
            self.due = due
            self.seq = seq
            self.fire = fire
        }

        func cancel() { cancelled = true }
    }

    var now: Double
    var timers: [Timer] = []
    var seq = 0

    init(now: Double) { self.now = now }

    func after(_ seconds: Double, _ fire: @escaping @MainActor () -> Void) -> any EngineTimer {
        seq += 1
        let t = Timer(due: now + max(0, seconds), seq: seq, fire: fire)
        timers.append(t)
        return t
    }

    /// Moves to the earliest timer and fires it; false when none is set.
    func fireNext() -> Bool {
        timers.removeAll { $0.cancelled }
        guard let t = timers.min(by: { ($0.due, $0.seq) < ($1.due, $1.seq) }) else { return false }
        timers.removeAll { $0 === t }
        now = max(now, t.due)
        t.fire()
        return true
    }

    var pending: Int { timers.filter { !$0.cancelled }.count }
}

/// A player that plays nothing: it reports what the rig tells it to.
final class FakePlayer: TunePlayer {
    var onEvent: (@MainActor (PlayerEvent) -> Void)?
    var calls: [String] = []
    var current: (url: URL, token: Int)?
    var next: (url: URL, token: Int)?
    var pendingPlay: (url: URL, token: Int)?
    var unplayable: Set<String> = []
    var paused = false
    var position = 0.0
    var repeatOne = false
    var volume = 1.0
    /// The level at each `play`, kept apart from `calls` so call counts hold.
    var volumeAtPlay: [Double] = []

    func play(_ url: URL, token: Int) {
        calls.append("play \(url.lastPathComponent)")
        volumeAtPlay.append(volume)
        current = nil
        next = nil
        pendingPlay = (url, token)
        paused = false
    }

    func setNext(_ url: URL?, token: Int) {
        calls.append("next \(url?.lastPathComponent ?? "-")")
        next = url.map { ($0, token) }
    }

    func advance() {
        calls.append("advance")
        guard let n = next else { return }
        current = n
        next = nil
        position = 0
        onEvent?(.started(token: n.token))
    }

    func setPaused(_ paused: Bool) {
        calls.append(paused ? "pause" : "resume")
        self.paused = paused
    }

    func seek(to seconds: Double) {
        calls.append("seek \(seconds)")
        position = seconds
    }

    func stop() {
        calls.append("stop")
        current = nil
        next = nil
        pendingPlay = nil
    }

    /// Reports the play asked for: started, or failed when the file is
    /// missing or marked unplayable.
    func deliver() -> Bool {
        guard let p = pendingPlay else { return false }
        pendingPlay = nil
        if unplayable.contains(p.url.lastPathComponent) || !FileManager.default.fileExists(atPath: p.url.path) {
            onEvent?(.failed(token: p.token, reason: "the file cannot be played"))
        } else {
            current = p
            position = 0
            onEvent?(.started(token: p.token))
        }
        return true
    }

    /// The playing item reaches its end.
    func finish() {
        guard let c = current else { return }
        if repeatOne {
            position = 0
            onEvent?(.looped(token: c.token))
            return
        }
        position = 0
        if let n = next {
            current = n
            next = nil
            onEvent?(.started(token: n.token))
        } else {
            current = nil
            onEvent?(.ended(token: c.token))
        }
    }

    var playing: String? { current?.url.lastPathComponent }
    var queuedNext: String? { next?.url.lastPathComponent }
}

final class FakeHolds: HoldSource {
    var hold: Hold?
    func current(memory: Bool) -> Hold? { hold == .memory && !memory ? nil : hold }
}

final class FakeProbe: SystemProbe {
    var bytes: Int64 = 7_000_000_000
    func footprint(pid: Int32) -> Int64? { bytes }
    func diskFree(near url: URL) -> Int64 { 100_000_000_000 }
}

/// Starts pretend server processes; their lines and exits reach the engine
/// when the rig delivers them, as a real process's would, later.
final class FakeLauncher: ServerLauncher {
    let ace: FakeAceServer
    var deviceLine: String? = "ggml_metal_device_init: GPU name:   MTL0 (Fake M0)"
    var noMetal = false
    var launches: [[String]] = []
    var processes: [FakeProcess] = []
    var pending: [@MainActor () async -> Void] = []

    init(ace: FakeAceServer) { self.ace = ace }

    var running: Int { processes.filter(\.alive).count }

    func launch(
        arguments: [String], onLine: @escaping @MainActor (String) -> Void, onExit: @escaping @MainActor (Int32) -> Void
    ) throws -> any ServerProcess {
        let p = FakeProcess(launcher: self, onLine: onLine, onExit: onExit)
        processes.append(p)
        launches.append(arguments)
        let port = arguments.last ?? ""
        let lines = (deviceLine.map { [$0] } ?? []) + (noMetal ? ["--device MTL0 not found. Available: BLAS CPU"] : ["[Server] Listening on 127.0.0.1:\(port)"])
        let noMetal = noMetal
        let ace = ace
        pending.append {
            guard p.alive else { return }
            if !noMetal { await ace.set(up: true) }
            for line in lines { p.onLine(line) }
            if noMetal { p.exit(1) }
        }
        return p
    }

    func deliver() async -> Bool {
        guard !pending.isEmpty else { return false }
        let work = pending
        pending = []
        for w in work { await w() }
        return true
    }

    /// The running server crashes.
    func crash() async {
        guard let p = processes.last(where: \.alive) else { return }
        await ace.set(up: false)
        p.onLine("GGML_ASSERT failed: a fake crash")
        p.exit(134)
    }
}

final class FakeProcess: ServerProcess {
    unowned let launcher: FakeLauncher
    let onLine: @MainActor (String) -> Void
    let onExit: @MainActor (Int32) -> Void
    var alive = true
    var stopped = false
    var killed = false

    init(launcher: FakeLauncher, onLine: @escaping @MainActor (String) -> Void, onExit: @escaping @MainActor (Int32) -> Void) {
        self.launcher = launcher
        self.onLine = onLine
        self.onExit = onExit
    }

    var serverPID: Int32? { alive ? 4242 : nil }

    func stop() {
        guard alive, !stopped else { return }
        stopped = true
        let ace = launcher.ace
        launcher.pending.append { [self] in
            await ace.set(up: false)
            exit(143)
        }
    }

    func kill() {
        guard alive, !killed else { return }
        killed = true
        stopped = true
        let ace = launcher.ace
        launcher.pending.append { [self] in
            await ace.set(up: false)
            exit(137)
        }
    }

    private var exitWaiters: [CheckedContinuation<Void, Never>] = []

    func exit(_ status: Int32) {
        guard alive else { return }
        alive = false
        onExit(status)
        let w = exitWaiters
        exitWaiters = []
        w.forEach { $0.resume() }
    }

    func waitForExit() async {
        if !alive { return }
        await withCheckedContinuation { exitWaiters.append($0) }
    }
}

extension Engine {
    /// Words for the chosen model, as before a model could be named.
    func composeWithWords(_ words: String, name: String) async -> Result<Void, Refusal> {
        await composeWithWords(words, name: name, model: nil)
    }
}

/// An engine on fakes in a folder of its own.
final class Rig {
    static let start = 1_795_390_000.0
    let root: URL
    let paths: EnginePaths
    let clock: ManualClock
    let player = FakePlayer()
    let holds = FakeHolds()
    let probe = FakeProbe()
    let ace = FakeAceServer()
    let host = FakeModelHost()
    let launcher: FakeLauncher
    let aceHTTP: LoopbackHTTPServer
    let hostHTTP: LoopbackHTTPServer
    var engine: Engine!
    var snapshots: [Snapshot] = []
    var token: (any SnapshotObservation)?
    /// The Large model's files and the shared ones.
    var modelFiles: [String: Data] = [:]
    /// The Small model's own file.
    var smallFile = (name: "fake-lm-small.gguf", data: Data())
    /// The Mac's installed memory the engine is told; from 24 GiB Large is suggested.
    var memoryBytes: Int64
    let seed: UInt64
    /// Replaces the fake launcher when set.
    var realLauncher: (any ServerLauncher)?

    static let genresText = """
    {
      "genres": [
        {
          "id": "jazz",
          "name": "Jazz",
          "caption": "a late-night jazz trio, brushed drums, upright bass",
          "turns": [
            "a walking bass solo",
            "muted trumpet",
            "a vibraphone chorus"
          ],
          "bpm": [90, 140],
          "moods": ["Blue", "Smoky"],
          "things": ["Avenue", "Lamp"]
        },
        {
          "id": "lofi",
          "name": "Lo-fi",
          "caption": "lo-fi beat, dusty vinyl, warm keys",
          "turns": [
            "rain in the background",
            "tape wobble"
          ],
          "bpm": [70, 92]
        }
      ]
    }

    """

    /// - Parameters:
    ///   - ready: whether the Large model and the shared files are in place already.
    ///   - keep: the newest-N rule's N.
    ///   - memory: the Mac's installed memory the engine is told.
    init(ready: Bool = true, keep: Int = 50, ahead: Int = 2, root: URL? = nil, genres: String = Rig.genresText, seed: UInt64 = 11,
         memory: Int64 = 64 << 30) async throws {
        memoryBytes = memory
        self.seed = seed
        self.root = root ?? FileManager.default.temporaryDirectory.appending(path: "tunes-engine-\(UUID().uuidString)", directoryHint: .isDirectory)
        paths = EnginePaths(
            support: self.root.appending(path: "support", directoryHint: .isDirectory),
            models: self.root.appending(path: "support/models", directoryHint: .isDirectory),
            caches: self.root.appending(path: "caches", directoryHint: .isDirectory),
            music: self.root.appending(path: "Music/Tunes", directoryHint: .isDirectory)
        )
        clock = ManualClock(now: Rig.start)
        launcher = FakeLauncher(ace: ace)
        let ace = ace
        let host = host
        aceHTTP = try await LoopbackHTTPServer { await ace.handle($0) }
        hostHTTP = try await LoopbackHTTPServer { await host.handle($0) }
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)

        // Invented model files, a few KiB each.
        let roles = ["lm", "dit", "text", "vae"]
        var entries: [String] = []
        for (i, role) in roles.enumerated() {
            let name = "fake-\(role).gguf"
            let data = Data((0..<(4096 + i * 1000)).map { UInt8(($0 * 31 + i) & 0xFF) })
            modelFiles[name] = data
            let sha = sha256Hex(data)
            entries.append(#"{"role": "\#(role)", "name": "\#(name)", "sha256": "\#(sha)", "bytes": \#(data.count)}"#)
        }
        smallFile.data = Data((0..<3000).map { UInt8(($0 * 17 + 5) & 0xFF) })
        let small = #"{"role": "lm", "name": "\#(smallFile.name)", "sha256": "\#(sha256Hex(smallFile.data))", "bytes": \#(smallFile.data.count)}"#
        await host.set(files: modelFiles.merging([smallFile.name: smallFile.data]) { a, _ in a })
        let pins = """
        {"model": {"name": "ACE-Step 1.5 Turbo", "base_url": "http://127.0.0.1:\(hostHTTP.port)",
        "revision": "rev", "shared": [\(entries.dropFirst().joined(separator: ", "))],
        "choices": [{"id": "small", "name": "Small", "variant": "0.6B Q8", "file": \(small),
        "ram_bytes": 4294967296, "suggested_from_bytes": 0},
        {"id": "large", "name": "Large", "variant": "4B Q8", "file": \(entries[0]),
        "ram_bytes": 8589934592, "suggested_from_bytes": 25769803776}], "silence_code": 35847},
        "keep": \(keep), "ahead": \(ahead), "duration": 12}
        """
        try Data(pins.utf8).write(to: self.root.appending(path: "pins.json"))
        if !Files.exists(self.root.appending(path: "genres-default.json")) {
            try Data(genres.utf8).write(to: self.root.appending(path: "genres-default.json"))
        }
        if ready { try placeModels() }
        make()
    }

    /// Places the Large model and the shared files.
    func placeModels() throws {
        try FileManager.default.createDirectory(at: paths.models, withIntermediateDirectories: true)
        for (name, data) in modelFiles { try data.write(to: paths.models.appending(path: name)) }
    }

    /// Places the Small model's file and the shared files.
    func placeSmall() throws {
        try FileManager.default.createDirectory(at: paths.models, withIntermediateDirectories: true)
        try smallFile.data.write(to: paths.models.appending(path: smallFile.name))
        for (name, data) in modelFiles where name != "fake-lm.gguf" { try data.write(to: paths.models.appending(path: name)) }
    }

    var environment: EngineEnvironment {
        let port = Int(aceHTTP.port)
        return EngineEnvironment(
            paths: paths, aceServer: URL(filePath: "/nonexistent/ace-server"),
            defaultGenres: root.appending(path: "genres-default.json"), pins: root.appending(path: "pins.json"),
            clock: clock, random: SplitMix64(seed: seed), player: player, launcher: realLauncher ?? launcher, holds: holds, probe: probe,
            timeZone: TimeZone(identifier: "UTC")!, freePort: { port }, memoryBytes: memoryBytes
        )
    }

    /// Builds the engine (again, for a restart) on the same folders.
    func make() {
        token?.cancel()
        snapshots = []
        engine = Engine(environment)
        token = engine.observe { [weak self] in self?.snapshots.append($0) }
    }

    var snap: Snapshot { engine.snapshot }

    /// Waits until the engine, the player and the launcher have nothing left
    /// to do at this moment.
    func settle() async {
        for _ in 0..<1000 {
            await engine.quiet()
            let a = await launcher.deliver()
            let b = player.deliver()
            if !a && !b {
                await engine.quiet()
                if launcher.pending.isEmpty && player.pendingPlay == nil { return }
            }
        }
        Issue.record("the rig never settled")
    }

    /// Lets time pass, timer by timer, until `done` holds.
    @discardableResult
    func run(until done: () -> Bool, steps: Int = 5000, sourceLocation: SourceLocation = #_sourceLocation) async -> Bool {
        for _ in 0..<steps {
            await settle()
            if done() { return true }
            if !clock.fireNext() {
                await settle()
                if done() { return true }
                Issue.record("nothing left to happen and the condition never held", sourceLocation: sourceLocation)
                return false
            }
        }
        Issue.record("the condition did not hold within \(steps) steps", sourceLocation: sourceLocation)
        return false
    }

    func send(_ c: Command) async {
        engine.send(c)
        await settle()
    }

    func genreDir(_ name: String) -> URL { paths.music.appending(path: name, directoryHint: .isDirectory) }

    /// A kept tune file (not real audio) made `minutesAgo` before the start.
    @discardableResult
    func keptTune(_ genre: String, day: Int, bpm: Int = 100, key: String = "A-minor") throws -> URL {
        let dir = genreDir(genre)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = String(format: "202601%02d-120000-%dbpm-%@.m4a", day, bpm, key)
        let url = dir.appending(path: name)
        try Data("not audio \(day)".utf8).write(to: url)
        return url
    }

    /// A kept tune that is real audio: a quiet tone, tagged as the engine tags.
    @discardableResult
    func realKeptTune(_ genre: String, day: Int, title: String, seconds: Double = 2) async throws -> URL {
        let dir = genreDir(genre)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: String(format: "202601%02d-120000-100bpm-A-minor.m4a", day))
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
        let frames = AVAudioFrameCount(48000 * seconds)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        for c in 0..<2 {
            for i in 0..<Int(frames) { buffer.floatChannelData![c][i] = Float(sin(Double(i) * 0.0576)) * 0.2 }
        }
        let raw = root.appending(path: "raw-\(day).m4a")
        try AudioWork.encode(buffer, to: raw)
        try await AudioWork.tag(raw, to: url, tags: TuneTags(title: title, genre: genre, bpm: 100, key: "A minor"))
        Files.remove(raw)
        return url
    }

    func tunes(_ genre: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: genreDir(genre).path)) ?? []).filter(TuneFiles.isTune).sorted()
    }

    /// Shuts the engine down while time passes, as it does in the app.
    func shutdown() async {
        var done = false
        let engine = engine!
        let task = Task {
            await engine.shutdown()
            done = true
        }
        for _ in 0..<10_000 where !done {
            await Task.yield()
            await settle()
            if !done { _ = clock.fireNext() }
        }
        await task.value
    }

    func close() async {
        await shutdown()
        token?.cancel()
        aceHTTP.stop()
        hostHTTP.stop()
        try? FileManager.default.removeItem(at: root)
    }
}

func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
