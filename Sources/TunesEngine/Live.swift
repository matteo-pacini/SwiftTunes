import AVFoundation
import Darwin
import TunesRules
import Foundation

/// The system clock; timers are sleeping tasks.
final class LiveClock: EngineClock {
    var now: Double { Date().timeIntervalSince1970 }

    func after(_ seconds: Double, _ fire: @escaping @MainActor () -> Void) -> any EngineTimer {
        let timer = LiveTimer()
        timer.task = Task {
            try? await Task.sleep(for: .seconds(max(0, seconds)))
            if !Task.isCancelled { fire() }
        }
        return timer
    }
}

final class LiveTimer: EngineTimer {
    var task: Task<Void, Never>?
    func cancel() { task?.cancel() }
}

/// Memory pressure, Low Power Mode and the thermal state, read when asked.
final class LiveHolds: HoldSource {
    func current(memory: Bool) -> Hold? {
        // 1 normal, 2 warn, 4 critical: the levels of the dispatch memory
        // pressure source, readable without one.
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if memory, sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0, level >= 2 {
            return .memory
        }
        let info = ProcessInfo.processInfo
        if info.isLowPowerModeEnabled { return .power }
        if info.thermalState == .serious || info.thermalState == .critical { return .heat }
        return nil
    }
}

final class LiveProbe: SystemProbe {
    func footprint(pid: Int32) -> Int64? {
        var info = rusage_info_v4()
        let rc = withUnsafeMutablePointer(to: &info) { p in
            p.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        return rc == 0 ? Int64(info.ri_phys_footprint) : nil
    }

    func diskFree(near url: URL) -> Int64 {
        Files.diskFree(near: url)
    }
}

/// Starts the server through tunes-lifeline, holding the write end of its
/// lifeline pipe.
final class LifelineLauncher: ServerLauncher {
    let lifeline: URL
    let server: URL

    init(lifeline: URL, server: URL) {
        self.lifeline = lifeline
        self.server = server
    }

    func launch(
        arguments: [String], onLine: @escaping @MainActor (String) -> Void, onExit: @escaping @MainActor (Int32) -> Void
    ) throws -> any ServerProcess {
        try LifelineProcess(argv: [lifeline.path, server.path] + arguments, onLine: onLine, onExit: onExit)
    }
}

struct SpawnError: Error, CustomStringConvertible {
    var description: String
}

final class LifelineProcess: ServerProcess {
    private var lifelineWrite: Int32
    private let lifelinePID: pid_t
    private(set) var serverPID: Int32?
    private var reader: Task<Void, Never>?

    init(argv: [String], onLine: @escaping @MainActor (String) -> Void, onExit: @escaping @MainActor (Int32) -> Void) throws {
        var life: [Int32] = [0, 0]
        var err: [Int32] = [0, 0]
        guard pipe(&life) == 0 else { throw SpawnError(description: String(cString: strerror(errno))) }
        guard pipe(&err) == 0 else {
            close(life[0]); close(life[1])
            throw SpawnError(description: String(cString: strerror(errno)))
        }
        // The write end must reach no child: its closing is the signal.
        _ = fcntl(life[1], F_SETFD, FD_CLOEXEC)
        _ = fcntl(err[0], F_SETFD, FD_CLOEXEC)

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, err[1], 2)
        if life[0] == 3 {
            posix_spawn_file_actions_addinherit_np(&actions, 3)
        } else {
            posix_spawn_file_actions_adddup2(&actions, life[0], 3)
        }
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        // Every other descriptor of this process stays out of the child.
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))

        let cArgs = argv.map { strdup($0) } + [nil]
        defer { cArgs.forEach { free($0) } }
        var pid: pid_t = 0
        let rc = posix_spawn(&pid, argv[0], &actions, &attr, cArgs, environ)
        close(life[0])
        close(err[1])
        guard rc == 0 else {
            close(life[1]); close(err[0])
            throw SpawnError(description: "\(argv[0]): \(String(cString: strerror(rc)))")
        }
        lifelineWrite = life[1]
        lifelinePID = pid

        let handle = FileHandle(fileDescriptor: err[0], closeOnDealloc: true)
        reader = Task { [weak self] in
            var first = true
            do {
                for try await line in handle.bytes.lines {
                    // Only the shim's own first line names the server: the
                    // server writes to the same pipe after it.
                    if first, let p = ServerLog.serverPID(line), p != pid { self?.serverPID = p }
                    first = false
                    onLine(line)
                }
            } catch {}
            let status = await LifelineProcess.reap(pid)
            onExit(status)
        }
    }

    func stop() {
        if lifelineWrite >= 0 {
            close(lifelineWrite)
            lifelineWrite = -1
        }
    }

    func kill() {
        // The shim made the server's pid its process group.
        if let pid = serverPID, pid > 1 { Darwin.kill(-pid, SIGKILL) }
        stop()
    }

    func waitForExit() async {
        await reader?.value
    }

    /// Waits for the shim's exit; its status as a shell gives it.
    @concurrent static func reap(_ pid: pid_t) async -> Int32 {
        var status: Int32 = 0
        while waitpid(pid, &status, 0) < 0 {
            if errno != EINTR { return -1 }
        }
        let signal = status & 0x7F
        return signal == 0 ? (status >> 8) & 0xFF : 128 + signal
    }
}

/// Plays through an AVQueuePlayer that holds the playing item and the next.
final class QueuePlayer: TunePlayer {
    var onEvent: (@MainActor (PlayerEvent) -> Void)?
    private let player = AVQueuePlayer()
    private var current: (item: AVPlayerItem, token: Int)?
    private var next: (item: AVPlayerItem, token: Int)?
    private var pendingNext: (url: URL?, token: Int)?
    private var loading: Int?
    private var loader: Task<Void, Never>?
    private var nextLoader: Task<Void, Never>?
    private var nextAsked: Int?
    private var paused = false
    private var observers: [any NSObjectProtocol] = []

    var repeatOne = false {
        didSet { player.actionAtItemEnd = repeatOne ? .none : .advance }
    }

    var volume = 1.0 {
        didSet { player.volume = Float(volume) }
    }

    /// The level the AVQueuePlayer itself holds.
    var playerVolume: Float { player.volume }

    init(muted: Bool = false) {
        player.isMuted = muted
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] note in
            let id = (note.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated { self?.itemEnded(id) }
        })
        observers.append(center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] note in
            let id = (note.object as AnyObject?).map(ObjectIdentifier.init)
            let reason = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription ?? "unknown error"
            MainActor.assumeIsolated { self?.itemFailed(id, reason: reason) }
        })
    }

    func play(_ url: URL, token: Int) {
        stop()
        loading = token
        paused = false
        loader = Task { [weak self] in
            let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
            let playable: Bool
            var reason = "the file cannot be played"
            do {
                playable = try await asset.load(.isPlayable)
            } catch {
                playable = false
                reason = error.localizedDescription
            }
            guard let self, self.loading == token else { return }
            self.loading = nil
            guard playable else {
                self.onEvent?(.failed(token: token, reason: reason))
                return
            }
            let item = AVPlayerItem(asset: asset)
            self.player.insert(item, after: nil)
            self.current = (item, token)
            if let p = self.pendingNext {
                self.pendingNext = nil
                self.setNext(p.url, token: p.token)
            }
            if !self.paused { self.player.play() }
            self.onEvent?(.started(token: token))
        }
    }

    func setNext(_ url: URL?, token: Int) {
        guard current != nil else {
            pendingNext = (url, token)
            return
        }
        nextLoader?.cancel()
        nextLoader = nil
        nextAsked = token
        if let n = next { player.remove(n.item) }
        next = nil
        guard let url else { return }
        // Queued only once it is known to play: an item that cannot load
        // would otherwise be moved to, and reported started, in silence.
        nextLoader = Task { [weak self] in
            let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
            var reason = "the file cannot be played"
            var playable = false
            do {
                playable = try await asset.load(.isPlayable)
            } catch {
                reason = error.localizedDescription
            }
            guard let self, !Task.isCancelled, self.nextAsked == token else { return }
            self.nextLoader = nil
            guard playable else {
                self.onEvent?(.failed(token: token, reason: reason))
                return
            }
            guard let cur = self.current else { return }
            let item = AVPlayerItem(asset: asset)
            self.player.insert(item, after: cur.item)
            self.next = (item, token)
        }
    }

    func advance() {
        guard let n = next else { return }
        player.advanceToNextItem()
        current = n
        next = nil
        if !paused { player.play() }
        onEvent?(.started(token: n.token))
    }

    func setPaused(_ paused: Bool) {
        self.paused = paused
        if paused { player.pause() } else if current != nil { player.play() }
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func stop() {
        loader?.cancel()
        loader = nil
        nextLoader?.cancel()
        nextLoader = nil
        nextAsked = nil
        loading = nil
        pendingNext = nil
        player.pause()
        player.removeAllItems()
        current = nil
        next = nil
    }

    var position: Double {
        let t = player.currentTime().seconds
        return t.isFinite ? max(0, t) : 0
    }

    private func itemEnded(_ id: ObjectIdentifier?) {
        guard let cur = current, id == ObjectIdentifier(cur.item) else { return }
        if repeatOne {
            player.seek(to: .zero)
            if !paused { player.play() }
            onEvent?(.looped(token: cur.token))
            return
        }
        if let n = next {
            // The queue player has moved on to it by itself.
            current = n
            next = nil
            onEvent?(.started(token: n.token))
        } else {
            current = nil
            onEvent?(.ended(token: cur.token))
        }
    }

    private func itemFailed(_ id: ObjectIdentifier?, reason: String) {
        guard let cur = current, id == ObjectIdentifier(cur.item) else { return }
        stop()
        onEvent?(.failed(token: cur.token, reason: reason))
    }
}
