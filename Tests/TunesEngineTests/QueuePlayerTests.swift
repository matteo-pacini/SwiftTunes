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
        let waiter = Waiter()
        player.onEvent = { e in
            events.append(e)
            waiter.poke()
        }
        // The real player: each wait is bounded, and a miss says what came.
        func until(_ check: @escaping () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
            let ok = await waiter.until(.seconds(10), check)
            #expect(ok, "the player did not report in time; events: \(events)", sourceLocation: sourceLocation)
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

    @Test func aNextItemThatCannotLoadIsReportedFailedNeverStarted() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "queue-player-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appending(path: "a.m4a")
        let broken = dir.appending(path: "broken.m4a")
        try Self.silence(a, seconds: 0.3)
        try Data("not audio at all".utf8).write(to: broken)

        let player = QueuePlayer(muted: true)
        var events: [PlayerEvent] = []
        let waiter = Waiter()
        player.onEvent = { e in
            events.append(e)
            waiter.poke()
        }
        // The real player: each wait is bounded, and a miss says what came.
        func until(_ check: @escaping () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
            let ok = await waiter.until(.seconds(10), check)
            #expect(ok, "the player did not report in time; events: \(events)", sourceLocation: sourceLocation)
        }
        player.play(a, token: 1)
        player.setNext(broken, token: 2)
        await until { events.contains(.ended(token: 1)) || events.contains(.started(token: 2)) }
        #expect(!events.contains(.started(token: 2)))
        #expect(events.contains { if case .failed(2, _) = $0 { true } else { false } })
        #expect(events.contains(.ended(token: 1)))
    }

    @Test func theLevelHoldsAcrossItemsAndStop() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "queue-player-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appending(path: "a.m4a")
        let b = dir.appending(path: "b.m4a")
        try Self.silence(a, seconds: 0.3)
        try Self.silence(b, seconds: 0.3)
        let player = QueuePlayer(muted: true)
        var events: [PlayerEvent] = []
        let waiter = Waiter()
        player.onEvent = { e in
            events.append(e)
            waiter.poke()
        }
        // The real player: each wait is bounded, and a miss says what came.
        func until(_ check: @escaping () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
            let ok = await waiter.until(.seconds(10), check)
            #expect(ok, "the player did not report in time; events: \(events)", sourceLocation: sourceLocation)
        }
        player.volume = 0.25
        #expect(player.playerVolume == 0.25)
        player.play(a, token: 1)
        player.setNext(b, token: 2)
        await until { events.contains(.started(token: 2)) }
        #expect(player.playerVolume == 0.25)
        player.stop()
        player.volume = 0.5
        player.play(a, token: 3)
        await until { events.contains(.started(token: 3)) }
        #expect(player.playerVolume == 0.5 && player.volume == 0.5)
        player.stop()
    }

    @Test func aRenameUnderThePlayingFileDoesNotStopIt() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "queue-player-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appending(path: "a.m4a")
        try Self.silence(a, seconds: 0.6)
        let player = QueuePlayer(muted: true)
        var events: [PlayerEvent] = []
        let waiter = Waiter()
        player.onEvent = { e in
            events.append(e)
            waiter.poke()
        }
        // The real player: each wait is bounded, and a miss says what came.
        func until(_ check: @escaping () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
            let ok = await waiter.until(.seconds(10), check)
            #expect(ok, "the player did not report in time; events: \(events)", sourceLocation: sourceLocation)
        }
        player.play(a, token: 1)
        await until { events.contains(.started(token: 1)) }
        try await AudioWork.retitle(a, to: "Renamed", part: dir.appending(path: ".a.m4a.part"))
        await until { events.count > 1 }
        #expect(events == [.started(token: 1), .ended(token: 1)])
    }
}
