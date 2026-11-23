import AVFoundation
import Foundation
import Testing
@testable import TunesEngine

/// The AVQueuePlayer behind the player protocol, on files of silence with
/// the player muted.
@Suite(.serialized, .timeLimit(.minutes(1))) struct QueuePlayerTests {
    static func silence(_ url: URL, seconds: Double) throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
        let frames = AVAudioFrameCount(48000 * seconds)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        try AudioWork.encode(buffer, to: url)
    }

    @Test func startNextEndAndFailure() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "queue-player-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appending(path: "a.m4a")
        let b = dir.appending(path: "b.m4a")
        try Self.silence(a, seconds: 0.3)
        try Self.silence(b, seconds: 0.3)

        let player = QueuePlayer(muted: true)
        var events: [PlayerEvent] = []
        var waiters: [(check: () -> Bool, cont: CheckedContinuation<Void, Never>)] = []
        player.onEvent = { e in
            events.append(e)
            let ready = waiters.filter { $0.check() }
            waiters.removeAll { $0.check() }
            ready.forEach { $0.cont.resume() }
        }
        func until(_ check: @escaping () -> Bool) async {
            if check() { return }
            await withCheckedContinuation { waiters.append((check, $0)) }
        }

        player.play(a, token: 1)
        player.setNext(b, token: 2)
        await until { events.contains(.ended(token: 2)) }
        #expect(events == [.started(token: 1), .started(token: 2), .ended(token: 2)])

        // A play replaced before it loads reports nothing.
        events = []
        player.play(a, token: 3)
        player.play(b, token: 4)
        await until { events.contains(.ended(token: 4)) }
        #expect(events == [.started(token: 4), .ended(token: 4)])

        events = []
        player.play(dir.appending(path: "missing.m4a"), token: 5)
        await until { !events.isEmpty }
        guard case .failed(5, _)? = events.first else {
            Issue.record("expected a failure, got \(events)")
            return
        }
    }
}
