import Foundation
import Testing
import TunesContract
@testable import TunesEngine
import TunesFakes
import TunesRules

@Suite(.serialized) struct PlayerTests {
    /// A rig with `count` kept Jazz tunes, shuffle off, Jazz picked.
    func keptRig(_ count: Int, shuffle: Bool = false, repeat mode: RepeatMode = .all) async throws -> (Rig, [String]) {
        let rig = try await Rig()
        for d in 1...count { try rig.keptTune("Jazz", day: d) }
        rig.make()
        await rig.send(.setShuffle(on: shuffle))
        await rig.send(.setRepeat(mode))
        await rig.send(.selectGenre(id: "jazz"))
        return (rig, rig.tunes("Jazz"))
    }

    @Test func aPickPlaysTheKeptTunesInTheOrderMade() async throws {
        let (rig, k) = try await keptRig(5)
        let s = rig.snap
        #expect(s.player == .playing && s.tune?.file == TuneFiles.stem(k[0]) && s.tune?.kept == true && s.tune?.pos == 1)
        // The whole rest of the round, in play order.
        #expect(s.queue.map(\.file) == k[1...].map(TuneFiles.stem))
        #expect(s.queue.map(\.pos) == [2, 3, 4, 5])
        #expect(s.keptPlaying && s.canNext && s.keptTotal == 5 && s.roundLeft == 4)
        #expect(rig.player.queuedNext == k[1])
        await rig.close()
    }

    @Test func nextAndIdle() async throws {
        let (rig, k) = try await keptRig(2, repeat: .off)
        await rig.send(.next)
        #expect(rig.snap.tune?.file == TuneFiles.stem(k[1]))
        #expect(!rig.snap.canNext)
        // The last of the round ends: the round is over with repeat off.
        rig.player.finish()
        await rig.settle()
        #expect(rig.snap.player == .none && rig.snap.ended && !rig.snap.stopped)
        // Play starts another round.
        await rig.send(.play)
        #expect(rig.snap.tune?.file == TuneFiles.stem(k[0]) && !rig.snap.ended)
        await rig.close()
    }

    @Test func nextIsIgnoredWithNothingAfter() async throws {
        let (rig, _) = try await keptRig(1)
        let before = rig.snapshots.count
        let calls = rig.player.calls.count
        await rig.send(.next)
        #expect(rig.snapshots.count == before && rig.player.calls.count == calls)
        await rig.close()
    }

    @Test func toggleStopPlayPause() async throws {
        let (rig, _) = try await keptRig(2)
        await rig.send(.pause)
        #expect(rig.snap.player == .paused && rig.player.paused)
        await rig.send(.play)
        #expect(rig.snap.player == .playing && !rig.player.paused)
        let n = rig.snapshots.count
        await rig.send(.play)
        #expect(rig.snapshots.count == n)
        await rig.send(.toggle)
        #expect(rig.snap.player == .paused)
        await rig.send(.stop)
        #expect(rig.snap.player == .none && rig.snap.stopped)
        await rig.send(.toggle)
        #expect(rig.snap.player == .playing && !rig.snap.stopped)
        await rig.close()
    }

    @Test func seekIsClampedToTheLength() async throws {
        let (rig, _) = try await keptRig(1)
        rig.engine.current?.length = 30
        await rig.send(.seek(to: 99))
        #expect(rig.player.calls.last == "seek 30.0")
        await rig.send(.seek(to: -4))
        #expect(rig.player.calls.last == "seek 0.0")
        await rig.close()
    }

    @Test func aLatePlayerEventAfterAGenrePickIsIgnored() async throws {
        let rig = try await Rig()
        try rig.keptTune("Jazz", day: 1)
        try rig.keptTune("Jazz", day: 2)
        try rig.keptTune("Lo-fi", day: 3)
        rig.make()
        await rig.send(.selectGenre(id: "jazz"))
        let jazzToken = try #require(rig.player.current?.token)
        let jazzNext = try #require(rig.player.next?.token)
        rig.engine.send(.selectGenre(id: "lofi"))
        // The old genre's tune reports, late, before the new one loads.
        rig.player.onEvent?(.started(token: jazzNext))
        rig.player.onEvent?(.ended(token: jazzToken))
        rig.player.onEvent?(.failed(token: jazzToken, reason: "late"))
        await rig.settle()
        #expect(rig.snap.genre == "lofi")
        #expect(rig.snap.tune?.file == "20260103-120000-100bpm-A-minor")
        #expect(rig.snap.player == .playing && rig.snap.error == nil)
        #expect(rig.snapshots.allSatisfy { $0.genre != "lofi" || $0.tune?.file.hasPrefix("20260103") != false })
        await rig.close()
    }

    @Test func anUnplayableTune() async throws {
        let rig = try await Rig()
        let url = try rig.keptTune("Jazz", day: 1)
        rig.player.unplayable = [url.lastPathComponent]
        rig.make()
        await rig.send(.selectGenre(id: "jazz"))
        #expect(rig.snap.error == "The tune could not be played: the file cannot be played")
        #expect(rig.snap.player == .none && rig.snap.stopped)
        await rig.close()
    }

    @Test func scrapUndoAndPlayCarryNames() async throws {
        let (rig, k) = try await keptRig(4)
        let playing = TuneFiles.stem(k[0])
        // A name that is no longer there does nothing.
        let before = rig.snapshots.count
        await rig.send(.scrapPlaying(name: "Something Else"))
        await rig.send(.scrapQueued(index: 0, name: TuneFiles.stem(k[3])))
        await rig.send(.playQueued(index: 1, name: TuneFiles.stem(k[1])))
        await rig.send(.playQueued(index: 9, name: TuneFiles.stem(k[1])))
        #expect(rig.snapshots.count == before)
        #expect(rig.tunes("Jazz") == k)

        await rig.send(.scrapPlaying(name: playing))
        #expect(rig.tunes("Jazz") == Array(k[1...]))
        #expect(rig.snap.undo == Undo(name: playing, until: rig.clock.now + 10, genre: "jazz"))
        #expect(rig.snap.tune?.file == TuneFiles.stem(k[1]))

        await rig.send(.undo)
        #expect(rig.tunes("Jazz") == k)
        #expect(rig.snap.undo == nil)
        // It plays next, without interrupting.
        #expect(rig.snap.tune?.file == TuneFiles.stem(k[1]))
        #expect(rig.snap.queue.first?.file == playing)

        // A queued scrap, finalised after 10 s.
        let q = rig.snap.queue
        await rig.send(.scrapQueued(index: 1, name: q[1].name))
        #expect(!rig.tunes("Jazz").contains(q[1].file + ".m4a"))
        #expect(rig.snap.undo?.name == q[1].name)
        #expect(await rig.run { rig.snap.undo == nil })
        #expect(rig.clock.now == Rig.start + 10)
        #expect(Files.list(rig.paths.caches.appending(path: "scrapped")).isEmpty)

        // Play it now, by name.
        let target = rig.snap.queue[1]
        await rig.send(.playQueued(index: 1, name: target.name))
        #expect(rig.snap.tune?.file == target.file)
        await rig.close()
    }

    @Test func aSecondScrapFinalisesTheFirst() async throws {
        let (rig, k) = try await keptRig(4)
        await rig.send(.scrapPlaying(name: TuneFiles.stem(k[0])))
        await rig.send(.scrapPlaying(name: TuneFiles.stem(k[1])))
        #expect(rig.snap.undo?.name == TuneFiles.stem(k[1]))
        #expect(Files.list(rig.paths.caches.appending(path: "scrapped")) == [k[1]])
        await rig.send(.undo)
        #expect(rig.tunes("Jazz") == Array(k[1...]))
        await rig.close()
    }

    @Test func failedMoves() async throws {
        let (rig, k) = try await keptRig(3)
        // The scrapped folder cannot be made: a file stands in its way.
        let scrapped = rig.paths.caches.appending(path: "scrapped")
        try Data().write(to: scrapped)
        await rig.send(.scrapPlaying(name: TuneFiles.stem(k[0])))
        #expect(rig.snap.error?.hasPrefix("could not scrap \(TuneFiles.stem(k[0])): ") == true)
        #expect(rig.snap.undo == nil && rig.tunes("Jazz") == k)
        try FileManager.default.removeItem(at: scrapped)

        await rig.send(.scrapPlaying(name: TuneFiles.stem(k[0])))
        #expect(rig.snap.error == nil && rig.snap.undo != nil)
        // The folder it came from refuses it back.
        let dir = rig.genreDir("Jazz")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        await rig.send(.undo)
        #expect(rig.snap.error == "could not bring \(TuneFiles.stem(k[0])) back: Permission denied")
        #expect(rig.snap.undo != nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        await rig.send(.undo)
        #expect(rig.snap.error == nil && rig.snap.undo == nil && rig.tunes("Jazz") == k)
        await rig.close()
    }

    @Test func shuffleRepeatAndTheQueue() async throws {
        let (rig, k) = try await keptRig(6, shuffle: true)
        #expect(rig.snap.shuffle && rig.snap.queue.count == 5 && rig.snap.roundLeft == 5)
        #expect(rig.snap.queue.allSatisfy { $0.pos == nil })
        await rig.send(.setShuffle(on: false))
        // What is left, back in the order made going round from the playing tune.
        let playing = try #require(rig.snap.tune?.file)
        #expect(rig.snap.queue.map(\.file) == Rounds.made(k.map(TuneFiles.stem).filter { $0 != playing }, after: playing))
        #expect(rig.snap.queue.allSatisfy { $0.pos != nil })
        await rig.send(.setRepeat(.one))
        #expect(rig.player.repeatOne && rig.snap.repeat == .one)
        let state = SavedState.parse(Files.read(rig.paths.support.appending(path: "state.json")))
        #expect(state.shuffle == false && state.repeat == .one)
        // Unchanged modes produce nothing.
        let n = rig.snapshots.count
        await rig.send(.setRepeat(.one))
        #expect(rig.snapshots.count == n)
        _ = k
        await rig.close()
    }

    @Test func volumeReachesThePlayerAndTheSnapshot() async throws {
        let (rig, _) = try await keptRig(2)
        #expect(rig.snap.volume == 1 && rig.player.volume == 1)
        await rig.send(.setVolume(to: 0.4, dragging: false))
        #expect(rig.player.volume == 0.4 && rig.snap.volume == 0.4)
        #expect(rig.snapshots.last?.volume == 0.4)
        await rig.close()
    }

    @Test(arguments: [(1.7, 1.0), (-0.2, 0.0), (0.0, 0.0), (1.0, 1.0)])
    func volumeIsClamped(_ asked: Double, _ applied: Double) async throws {
        let (rig, _) = try await keptRig(1)
        await rig.send(.setVolume(to: 0.5, dragging: false))
        await rig.send(.setVolume(to: asked, dragging: false))
        #expect(rig.player.volume == applied && rig.snap.volume == applied)
        await rig.close()
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func aVolumeThatIsNotFiniteIsIgnored(_ asked: Double) async throws {
        let (rig, _) = try await keptRig(1)
        await rig.send(.setVolume(to: 0.5, dragging: false))
        let n = rig.snapshots.count
        await rig.send(.setVolume(to: asked, dragging: false))
        #expect(rig.player.volume == 0.5 && rig.snap.volume == 0.5 && rig.snapshots.count == n)
        await rig.close()
    }

    @Test func anUnchangedVolumeProducesNoSnapshot() async throws {
        let (rig, _) = try await keptRig(1)
        await rig.send(.setVolume(to: 0.5, dragging: true))
        let n = rig.snapshots.count
        #expect(rig.snapshots.last?.volume == 0.5)
        await rig.send(.setVolume(to: 0.5, dragging: true))
        await rig.send(.setVolume(to: 0.5, dragging: false))
        #expect(rig.snapshots.count == n)
        await rig.close()
    }

    @Test func aDragWritesTheStateFileOnceOnRelease() async throws {
        let (rig, _) = try await keptRig(1)
        let file = rig.paths.support.appending(path: "state.json")
        Files.remove(file)
        for level in [0.9, 0.8, 0.7] {
            await rig.send(.setVolume(to: level, dragging: true))
            #expect(rig.player.volume == level && rig.snap.volume == level)
            #expect(!Files.exists(file))
        }
        // Released where the last step left it: no new snapshot, yet saved.
        await rig.send(.setVolume(to: 0.7, dragging: false))
        #expect(SavedState.parse(Files.read(file)).volume == 0.7)
        await rig.close()
    }

    @Test func aDragNeverReleasedIsSavedAtShutdown() async throws {
        let (rig, _) = try await keptRig(1)
        let file = rig.paths.support.appending(path: "state.json")
        await rig.send(.setVolume(to: 0.3, dragging: true))
        #expect(SavedState.parse(Files.read(file)).volume == 1)
        await rig.shutdown()
        #expect(SavedState.parse(Files.read(file)).volume == 0.3)
        await rig.close()
    }

    @Test func repeatOnAfterTheRoundEndedStartsAnother() async throws {
        let (rig, _) = try await keptRig(1, repeat: .off)
        rig.player.finish()
        await rig.settle()
        #expect(rig.snap.ended)
        await rig.send(.setRepeat(.all))
        #expect(!rig.snap.ended && rig.snap.player == .playing)
        await rig.close()
    }

    @Test func pinsShareAndExport() async throws {
        let (rig, k) = try await keptRig(3)
        let name = TuneFiles.stem(k[0])
        let info = try await rig.engine.shareInfo(for: TuneTarget(name: name, index: nil)).get()
        #expect(info.name == name && info.genre == "Jazz" && info.bpm == 100 && info.key == "A minor")
        #expect(info.path == rig.genreDir("Jazz").appending(path: k[0]))
        #expect(info.exportPath.lastPathComponent == "Jazz - \(name).m4a" && !info.pinned)

        let pin = await rig.engine.setPinned(true, for: TuneTarget(name: name, index: nil))
        #expect(pin == .success(PinResult(on: true, name: name)))
        await rig.settle()
        #expect(rig.snap.tune?.pinned == true)
        #expect(Files.exists(rig.genreDir("Jazz").appending(path: ".\(k[0]).pin")))

        let out = try await rig.engine.exportCopy(of: TuneTarget(name: name, index: nil)).get()
        #expect(out.lastPathComponent == "Jazz - \(name).m4a")
        #expect(FileManager.default.contents(atPath: out.path) == FileManager.default.contents(atPath: info.path.path))
        let second = try await rig.engine.exportCopy(of: TuneTarget(name: name, index: nil)).get()
        #expect(second.lastPathComponent == "Jazz - \(name) (2).m4a")
        #expect(!Files.list(rig.paths.music.appending(path: "Exports")).contains { $0.hasPrefix(".") })

        let gone = Refusal(field: nil, text: "That tune is no longer there.")
        #expect(await rig.engine.shareInfo(for: TuneTarget(name: "Other", index: nil)) == .failure(gone))
        #expect(await rig.engine.setPinned(true, for: TuneTarget(name: name, index: 0)) == .failure(gone))
        // A queue row by index and name.
        let q0 = rig.snap.queue[0]
        #expect(try await rig.engine.shareInfo(for: TuneTarget(name: q0.name, index: 0)).get().name == q0.name)
        // A tune of the genre that is neither playing nor queued, by file stem.
        #expect(try await rig.engine.shareInfo(for: TuneTarget(name: TuneFiles.stem(k[2]), index: nil)).get().name == TuneFiles.stem(k[2]))

        // A pinned tune survives a scrap and undo pinned.
        await rig.send(.scrapPlaying(name: name))
        #expect(!Files.exists(rig.genreDir("Jazz").appending(path: ".\(k[0]).pin")))
        await rig.send(.undo)
        #expect(Files.exists(rig.genreDir("Jazz").appending(path: ".\(k[0]).pin")))
        await rig.close()
    }

    @Test func aFirstTuneStartsByItselfAndStopHoldsIt() async throws {
        let rig = try await Rig()
        await rig.send(.selectGenre(id: "jazz"))
        await rig.send(.stop)
        #expect(rig.snap.stopped)
        await rig.send(.setComposer(on: true))
        #expect(await rig.run { rig.snap.ready == 1 })
        #expect(rig.snap.player == .none)
        await rig.send(.toggle)
        #expect(rig.snap.player == .playing && rig.snap.ready == 0)
        await rig.close()
    }

    @Test func keepProtectsWhatPlaysAndWhatIsPinned() async throws {
        let rig = try await Rig(keep: 3, ahead: 1)
        for d in 1...6 { try rig.keptTune("Jazz", day: d) }
        let k = rig.tunes("Jazz")
        try Data().write(to: rig.genreDir("Jazz").appending(path: ".\(k[1]).pin"))
        rig.make()
        await rig.send(.setShuffle(on: false))
        await rig.send(.selectGenre(id: "jazz"))
        await rig.send(.setComposer(on: true))
        #expect(await rig.run { rig.snap.ready == 1 })
        // Seven tunes, one pinned: six count and three may stay. Day 1 plays;
        // the new one, days 2 to 4 are queued; days 5 and 6 are all that may go.
        let left = rig.tunes("Jazz")
        #expect(left.count == 5)
        #expect(Set(k[0...3]).isSubset(of: Set(left)))
        #expect(!left.contains(k[4]) && !left.contains(k[5]))
        #expect(Files.exists(rig.genreDir("Jazz").appending(path: ".\(k[1]).pin")))
        await rig.close()
    }
}
