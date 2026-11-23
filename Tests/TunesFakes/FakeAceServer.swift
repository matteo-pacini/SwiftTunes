import Foundation

/// 16-bit PCM WAV files, made in Swift.
public enum WAV {
    /// A WAV of interleaved 16-bit samples.
    public static func make(rate: Int, channels: Int, samples: [Int16]) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes)
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(UInt16(channels))
        u32(UInt32(rate)); u32(UInt32(rate * channels * 2)); u16(UInt16(channels * 2)); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(bytes)
        samples.withUnsafeBytes { raw in
            for s in raw.bindMemory(to: Int16.self) { u16(UInt16(bitPattern: s)) }
        }
        return d
    }

    /// A 440 Hz tone at `rate`, stereo; each 0.2 s code slot is silent where
    /// `silent` says so and at `quietLevel` of full scale where `quiet` does.
    public static func tone(rate: Int, slots: [Bool], quiet: [Bool] = [], level: Double = 0.5, quietLevel: Double = 0.0005) -> Data {
        let perSlot = rate / 5
        var samples: [Int16] = []
        samples.reserveCapacity(slots.count * perSlot * 2)
        for (i, silent) in slots.enumerated() {
            let a = silent ? 0 : (i < quiet.count && quiet[i] ? quietLevel : level)
            for n in 0..<perSlot {
                let t = Double(i * perSlot + n) / Double(rate)
                let v = Int16(clamping: Int((sin(2 * .pi * 440 * t) * a * 32767).rounded()))
                samples.append(v)
                samples.append(v)
            }
        }
        return make(rate: rate, channels: 2, samples: samples)
    }
}

/// A stand-in for ace-server's HTTP API: /health, /lm, /synth, /job with
/// result and cancel, jobs that run for a number of polls, plans with the
/// silence code, a multipart reply holding a WAV.
public actor FakeAceServer {
    public enum Kind: Sendable, Equatable {
        /// A plan with a 2 s silent tail, rendered as a tone.
        case normal
        /// A plan with 6.4 s of silence in the middle.
        case silent
        /// A normal plan rendered with 6 s of near silence in the middle.
        case quiet
        /// The job ends with status "failed".
        case fail
        /// The server crashes while the job is polled.
        case exit
        /// Asked to write words, it writes none: `[Instrumental]`.
        case declines
        /// Asked to write words, it writes three lines.
        case thin
    }

    public static let silenceCode = 35847
    public static let boundary = "ace-batch-boundary"

    /// The kind of each plan in turn; once used up, `normal`.
    public var kinds: [Kind] = []
    /// Polls a job answers "running" before it is done.
    public var runningPolls = 1
    /// Health checks answered "loading" before "ok".
    public var loadingHealth = 0
    public var rate = 48000
    /// Hold the reply to /lm until `releaseLM()`.
    public var holdLM = false
    private var lmHeld: [CheckedContinuation<Void, Never>] = []
    private var lmHeldWaiters: [CheckedContinuation<Void, Never>] = []
    public func set(holdLM: Bool) { self.holdLM = holdLM }

    /// Returns once a reply to /lm is being held.
    public func untilLMHeld() async {
        if !lmHeld.isEmpty { return }
        await withCheckedContinuation { lmHeldWaiters.append($0) }
    }

    public func releaseLM() {
        holdLM = false
        let h = lmHeld
        lmHeld = []
        h.forEach { $0.resume() }
    }

    /// Polls a cancelled job still answers "running" before "cancelled".
    public var cancelPolls = 0
    public func set(cancelPolls: Int) { self.cancelPolls = cancelPolls }
    /// Called when a job of kind `exit` is polled, before the connection drops.
    public var onCrash: (@Sendable () async -> Void)?

    private var lmBodies: [[String: Any]] = []
    private var synthBodies: [[String: Any]] = []
    public private(set) var cancelled: [Int] = []
    public private(set) var healthChecks = 0
    private var jobs: [Int: Job] = [:]
    private var nextID = 1

    struct Job {
        var kind: Kind
        var stage: String
        var polls = 0
        var status = "running"
        var result: Data
    }

    public init() {}

    public func set(kinds: [Kind]) { self.kinds = kinds }
    public func set(runningPolls: Int) { self.runningPolls = runningPolls }
    public func set(onCrash: (@Sendable () async -> Void)?) { self.onCrash = onCrash }
    public func set(loadingHealth: Int) { self.loadingHealth = loadingHealth }
    /// Whether a server process is up; while it is not, every request is dropped.
    public private(set) var up = false
    public func set(up: Bool) { self.up = up }

    public var lmCount: Int { lmBodies.count }
    public var lmBPMs: [Int] { lmBodies.compactMap { $0["bpm"] as? Int } }
    public var lmCaptions: [String] { lmBodies.compactMap { $0["caption"] as? String } }
    /// The lyrics of each /lm request, as sent.
    public var lmLyrics: [String] { lmBodies.map { $0["lyrics"] as? String ?? "(none)" } }
    /// The vocal_language of each /lm request, nil where none was sent.
    public var lmLanguages: [String?] { lmBodies.map { $0["vocal_language"] as? String } }
    /// The words the fake writes when asked to.
    public static let words = """
    [Verse]
    walking home under amber lights
    the city hums a quiet tune
    [Chorus]
    hold on, hold on to the night
    we are dancing on the moon
    [Verse]
    every window keeps a secret
    every street a little song
    [Chorus]
    hold on, hold on to the night
    """
    public var synthFormats: [String] { synthBodies.compactMap { $0["output_format"] as? String } }

    public func handle(_ r: HTTPRequest) async -> HTTPResponse {
        guard up else { return .dropped }
        switch (r.method, r.path) {
        case ("GET", "/health"):
            healthChecks += 1
            return .json(healthChecks <= loadingHealth ? #"{"status":"loading"}"# : #"{"status":"ok"}"#)
        case ("POST", "/lm"):
            let body = (try? JSONSerialization.jsonObject(with: r.body)) as? [String: Any] ?? [:]
            lmBodies.append(body)
            let kind = kinds.isEmpty ? .normal : kinds.removeFirst()
            let duration = body["duration"] as? Int ?? 180
            let bpm = body["bpm"] as? Int ?? 90
            // Words as the three request shapes get them: kept for no voice,
            // written when empty, kept as given otherwise.
            let asked = body["lyrics"] as? String ?? ""
            let lyrics: String
            switch (asked, kind) {
            case ("[Instrumental]", _): lyrics = "[Instrumental]"
            case ("", .declines): lyrics = "[Instrumental]"
            case ("", .thin): lyrics = "[Verse]\nla la la\nla la la\nhold on"
            case ("", _): lyrics = Self.words
            default: lyrics = asked
            }
            let plan = Self.plan(kind: kind, duration: duration, bpm: bpm, key: lmBodies.count % 2 == 1 ? "C# minor" : "F major",
                                 lyrics: lyrics, language: body["vocal_language"] as? String)
            if holdLM {
                await withCheckedContinuation { cont in
                    lmHeld.append(cont)
                    let w = lmHeldWaiters
                    lmHeldWaiters = []
                    w.forEach { $0.resume() }
                }
            }
            return start(kind: kind, stage: "lm", result: Data(plan.utf8))
        case ("POST", "/synth"):
            let body = (try? JSONSerialization.jsonObject(with: r.body)) as? [String: Any] ?? [:]
            synthBodies.append(body)
            let codes = (body["audio_codes"] as? String ?? "").split(separator: ",").compactMap { Int($0) }
            let slots = codes.map { $0 == Self.silenceCode }
            let kind = (body["fake_kind"] as? String).flatMap(Self.kind(named:)) ?? .normal
            var quiet: [Bool] = []
            if kind == .quiet {
                // 6 s, clear of the tail the engine cuts.
                quiet = slots.indices.map { $0 >= 5 && $0 < 35 }
            }
            let wav = WAV.tone(rate: rate, slots: slots, quiet: quiet)
            var reply = Data("--\(Self.boundary)\r\nContent-Type: audio/wav\r\n\r\n".utf8)
            reply.append(wav)
            reply.append(Data("\r\n--\(Self.boundary)\r\nContent-Type: application/octet-stream\r\nContent-Disposition: form-data; name=\"latent\"\r\n\r\n".utf8))
            reply.append(Data([0, 1, 2, 3]))
            reply.append(Data("\r\n--\(Self.boundary)--\r\n".utf8))
            return start(kind: kind == .fail || kind == .exit ? kind : .normal, stage: "synth", result: reply)
        case ("GET", "/job"), ("POST", "/job"):
            guard let id = number(r.query["id"]), var job = jobs[id] else { return .json(#"{"error":"no such job"}"#, status: 404) }
            if r.query["cancel"] == "1" {
                cancelled.append(id)
                job.status = "cancelling"
                job.polls = 0
                jobs[id] = job
                return .json(#"{"status":"cancelled"}"#)
            }
            if job.status == "cancelling" {
                job.polls += 1
                if job.polls > cancelPolls { job.status = "cancelled" }
                jobs[id] = job
                return .json(job.status == "cancelled" ? #"{"status":"cancelled"}"# : #"{"status":"running"}"#)
            }
            if r.query["result"] == "1" {
                return HTTPResponse(status: 200, headers: [("Content-Type", job.stage == "lm" ? "application/json" : "multipart/mixed; boundary=\(Self.boundary)")], body: job.result)
            }
            if job.status == "running" {
                job.polls += 1
                if job.polls > runningPolls {
                    switch job.kind {
                    case .fail: job.status = "failed"
                    case .exit:
                        jobs[id] = job
                        await onCrash?()
                        return .dropped
                    default: job.status = "done"
                    }
                }
            }
            jobs[id] = job
            return .json(#"{"status":"\#(job.status)"}"#)
        default:
            return .json(#"{"error":"not found"}"#, status: 404)
        }
    }

    /// Job ids are given as text with this prefix, when set.
    public var idPrefix: String?
    public func set(idPrefix: String?) { self.idPrefix = idPrefix }

    private func start(kind: Kind, stage: String, result: Data) -> HTTPResponse {
        let id = nextID
        nextID += 1
        jobs[id] = Job(kind: kind, stage: stage, result: result)
        if let p = idPrefix { return .json(#"{"id":"\#(p)\#(id)"}"#) }
        return .json(#"{"id":\#(id)}"#)
    }

    private func number(_ id: String?) -> Int? {
        guard var id else { return nil }
        if let p = idPrefix, id.hasPrefix(p) { id = String(id.dropFirst(p.count)) }
        return Int(id)
    }

    static func kind(named s: String) -> Kind? {
        switch s {
        case "quiet": .quiet
        case "fail": .fail
        case "exit": .exit
        default: nil
        }
    }

    /// The plan the language model would write: `duration` seconds of codes
    /// at five a second, the silence code where silent.
    static func plan(kind: Kind, duration: Int, bpm: Int, key: String, lyrics: String = "[Instrumental]", language: String? = nil) -> String {
        let n = duration * 5
        var codes = (0..<n).map { 100 + ($0 * 37) % 60000 }
        if kind == .silent {
            // Clear of the 2 s tail, with sound on both sides.
            let start = max(1, (n - 10 - 32) / 2)
            for i in start..<min(n - 11, start + 32) { codes[i] = silenceCode }
        }
        for i in max(0, n - 10)..<n { codes[i] = silenceCode }
        let text = codes.map(String.init).joined(separator: ",") + ","
        var extra = ""
        switch kind {
        case .quiet: extra = #", "fake_kind": "quiet""#
        case .fail: extra = #", "fake_kind": "fail""#
        case .exit: extra = #", "fake_kind": "exit""#
        default: break
        }
        let words = String(decoding: (try? JSONSerialization.data(withJSONObject: lyrics, options: .fragmentsAllowed)) ?? Data("\"\"".utf8), as: UTF8.self)
        let lang = language.map { #", "vocal_language": "\#($0)""# } ?? ""
        return #"[{"caption": "x", "audio_codes": "\#(text)", "bpm": \#(bpm), "keyscale": "\#(key)", "duration": \#(duration), "lyrics": \#(words)\#(lang)\#(extra)}]"#
    }
}

/// A stand-in for the model host: files at /resolve/<revision>/<name>, with
/// Range support, failures on demand and a reply that can be held half sent.
public actor FakeModelHost {
    public var files: [String: Data] = [:]
    public var revision = "rev"
    /// Statuses for the next requests, in turn.
    public var failures: [Int] = []
    /// Ignore Range and send the whole file with 200.
    public var ignoreRange = false
    /// Hold each reply after this many body bytes until `release()`.
    public var holdAfter: Int?
    public var corrupt: Set<String> = []
    public private(set) var ranges: [String?] = []
    public private(set) var requests: [String] = []
    private var held: [CheckedContinuation<Void, Never>] = []
    private var heldCount = 0

    public init() {}

    public func set(files: [String: Data]) { self.files = files }
    public func set(failures: [Int]) { self.failures = failures }
    public func set(ignoreRange: Bool) { self.ignoreRange = ignoreRange }
    public func set(holdAfter: Int?) { self.holdAfter = holdAfter }
    public func set(corrupt: Set<String>) { self.corrupt = corrupt }

    /// How many replies are waiting half sent.
    public var waiting: Int { heldCount }
    private var heldWaiters: [CheckedContinuation<Void, Never>] = []

    /// Returns once a reply is being held.
    public func untilHeld() async {
        if heldCount > 0 { return }
        await withCheckedContinuation { heldWaiters.append($0) }
    }

    public func release() {
        holdAfter = nil
        let h = held
        held = []
        h.forEach { $0.resume() }
    }

    private func hold() async {
        heldCount += 1
        let w = heldWaiters
        heldWaiters = []
        w.forEach { $0.resume() }
        if holdAfter != nil {
            await withCheckedContinuation { held.append($0) }
        }
        heldCount -= 1
    }

    public func handle(_ r: HTTPRequest) async -> HTTPResponse {
        requests.append(r.path)
        ranges.append(r.headers["range"])
        if !failures.isEmpty { return HTTPResponse(status: failures.removeFirst()) }
        let prefix = "/resolve/\(revision)/"
        guard r.path.hasPrefix(prefix), var data = files[String(r.path.dropFirst(prefix.count))] else {
            return HTTPResponse(status: 404)
        }
        if corrupt.contains(String(r.path.dropFirst(prefix.count))), !data.isEmpty {
            data[data.count - 1] ^= 0xFF
        }
        var status = 200
        var headers: [(String, String)] = []
        if !ignoreRange, let range = r.headers["range"], range.hasPrefix("bytes="), range.hasSuffix("-"),
           let from = Int(range.dropFirst(6).dropLast()) {
            guard from < data.count else {
                return HTTPResponse(status: 416, headers: [("Content-Range", "bytes */\(data.count)")])
            }
            headers.append(("Content-Range", "bytes \(from)-\(data.count - 1)/\(data.count)"))
            data = data.subdata(in: from..<data.count)
            status = 206
        }
        var response = HTTPResponse(status: status, headers: headers, body: data)
        if let after = holdAfter, after < data.count {
            response.parts = [data.prefix(after), data.dropFirst(after)].map { Data($0) }
            response.between = { _ in await self.hold() }
        }
        return response
    }
}
