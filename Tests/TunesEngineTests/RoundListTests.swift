import Foundation
import Testing
import TunesContract
@testable import TunesEngine
import TunesFakes
import TunesRules

/// The round as one list: played, the playing tune, then the queue.
@Suite(.serialized, .timeLimit(.minutes(1))) struct RoundListTests {
    func rig(_ count: Int, shuffle: Bool = true, repeat mode: RepeatMode = .all, seed: UInt64 = 11, ahead: Int = 2) async throws -> Rig {
        let rig = try await Rig(ahead: ahead, seed: seed)
        for d in 1...count { try rig.keptTune("Jazz", day: d) }
        rig.make()
        await rig.send(.setShuffle(on: shuffle))
        await rig.send(.setRepeat(mode))
        await rig.send(.selectGenre(id: "jazz"))
        return rig
    }

    /// The round's list as files: played, the playing tune, the queue.
    func list(_ rig: Rig) -> [String] {
        let s = rig.snap
        return s.played.map(\.file) + (s.tune.map { [$0.file] } ?? []) + s.queue.map(\.file)
    }

    func finish(_ rig: Rig, _ n: Int = 1) async {
        for _ in 0..<n {
            rig.player.finish()
            await rig.settle()
        }
    }

    @Test func playedTunesStayInTheirPlaces() async throws {
        let rig = try await rig(6)
        let round = list(rig)
        #expect(round.count == 6 && rig.snap.played.isEmpty)
        for step in 1...5 {
            await finish(rig)
            #expect(list(rig) == round, "step \(step)")
            #expect(rig.snap.played.count == step && rig.snap.tune?.file == round[step])
            #expect(rig.snap.roundLeft == 5 - step && rig.snap.queue.count == 5 - step)
        }
        #expect(rig.snap.canNext == true)
        await rig.close()
    }

    @Test func aNewTuneGoesRightAfterThePlayingOne() async throws {
        let rig = try await rig(5, ahead: 1)
        await finish(rig, 2)
        let before = list(rig)
        await rig.send(.setComposer(on: true))
        #expect(await rig.run { rig.snap.ready == 1 })
        await rig.send(.setComposer(on: false))
        let new = try #require(rig.snap.queue.first)
        #expect(new.new)
        var expected = before
        expected.insert(new.file, at: 3)
        #expect(list(rig) == expected)
        await rig.close()
    }

    @Test func scrapAndUndoKeepPlaces() async throws {
        let rig = try await rig(6)
        await finish(rig, 3)
        let round = list(rig)
        // A queued tune.
        let q1 = rig.snap.queue[1]
        await rig.send(.scrapQueued(index: 1, name: q1.name))
        #expect(list(rig) == round.filter { $0 != q1.file })
        await rig.send(.undo)
        #expect(list(rig) == round)
        // A played tune.
        let p1 = rig.snap.played[1]
        await rig.send(.scrapPlayed(index: 1, name: "not its name"))
        #expect(list(rig) == round)
        await rig.send(.scrapPlayed(index: 1, name: p1.name))
        #expect(list(rig) == round.filter { $0 != p1.file } && rig.snap.undo?.name == p1.name)
        await rig.send(.undo)
        #expect(list(rig) == round && rig.snap.played[1].file == p1.file)
        await rig.close()
    }

    @Test(arguments: [true, false])
    func shuffleRedrawsOnlyTheQueue(startShuffled: Bool) async throws {
        let rig = try await rig(8, shuffle: startShuffled)
        await finish(rig, 3)
        let played = rig.snap.played.map(\.file)
        let playing = rig.snap.tune?.file
        let queued = Set(rig.snap.queue.map(\.file))
        await rig.send(.setShuffle(on: !startShuffled))
        #expect(rig.snap.played.map(\.file) == played && rig.snap.tune?.file == playing)
        #expect(Set(rig.snap.queue.map(\.file)) == queued)
        await rig.close()
    }

    @Test func previousRestartsAfterThreeSeconds() async throws {
        let rig = try await rig(4)
        await finish(rig, 2)
        let round = list(rig)
        rig.player.position = 1
        await rig.send(.refresh)
        rig.clock.now += 2.5
        // 3.5 s in by the clock: it starts over.
        await rig.send(.previous)
        #expect(rig.player.calls.last == "seek 0.0" && list(rig) == round)
        #expect(rig.snap.pos == 0)
        await rig.close()
    }

    @Test func previousWithinThreeSecondsGoesBackOne() async throws {
        let rig = try await rig(5, ahead: 1)
        await finish(rig, 2)
        let round = list(rig)
        let wasPlaying = try #require(rig.snap.tune?.file)
        let lastPlayed = try #require(rig.snap.played.last?.file)
        rig.player.position = 1
        await rig.send(.refresh)
        await rig.send(.previous)
        #expect(rig.snap.tune?.file == lastPlayed && rig.snap.queue.first?.file == wasPlaying)
        #expect(list(rig) == round && rig.snap.played.count == 1)
        // A new tune made now goes behind the tune put back.
        await rig.send(.setComposer(on: true))
        #expect(await rig.run { rig.snap.ready == 1 })
        #expect(rig.snap.queue.first?.file == wasPlaying && rig.snap.queue[1].new)
        await rig.close()
    }

    @Test func previousWithNothingPlayedRestarts() async throws {
        let rig = try await rig(3)
        let round = list(rig)
        await rig.send(.previous)
        #expect(rig.player.calls.last == "seek 0.0" && list(rig) == round)
        await rig.close()
    }

    @Test func previousNeverReachesAScrappedTuneOrAnEarlierRound() async throws {
        let rig = try await rig(4)
        await finish(rig, 2)
        let played = rig.snap.played
        await rig.send(.scrapPlayed(index: 1, name: played[1].name))
        await rig.send(.previous)
        #expect(rig.snap.tune?.file == played[0].file)
        await rig.send(.previous)
        // Nothing before it this round: it starts over.
        #expect(rig.snap.tune?.file == played[0].file && rig.player.calls.last == "seek 0.0")
        await rig.close()
    }

    @Test func previousIsNothingWithoutATune() async throws {
        let rig = try await rig(3)
        await rig.send(.stop)
        let n = rig.snapshots.count
        await rig.send(.previous)
        #expect(rig.snapshots.count == n)
        await rig.close()
    }

    @Test func playItAgainJumpsBack() async throws {
        let rig = try await rig(6)
        await finish(rig, 4)
        let round = list(rig)
        let target = rig.snap.played[1]
        await rig.send(.playPlayed(index: 1, name: "someone else"))
        #expect(rig.snap.tune?.file == round[4])
        await rig.send(.playPlayed(index: 1, name: target.name))
        #expect(rig.snap.tune?.file == target.file)
        #expect(rig.snap.played.map(\.file) == [round[0]])
        #expect(rig.snap.queue.map(\.file) == Array(round[2...]))
        #expect(list(rig) == round)
        await rig.close()
    }

    @Test func repeatAllDrawsANewRoundAtTheEnd() async throws {
        let rig = try await rig(4, repeat: .all)
        let first = list(rig)
        await finish(rig, 3)
        #expect(rig.snap.queue.isEmpty && rig.snap.played.count == 3 && rig.snap.canNext)
        await finish(rig)
        #expect(rig.snap.played.isEmpty && rig.snap.tune?.file != first.last)
        #expect(Set(list(rig)) == Set(first) && rig.snap.queue.count == 3)
        await rig.close()
    }

    @Test func repeatOffEndsWithTheWholeRoundPlayed() async throws {
        let rig = try await rig(4, repeat: .off)
        let round = list(rig)
        await finish(rig, 4)
        #expect(rig.snap.ended && rig.snap.tune == nil && rig.snap.queue.isEmpty)
        #expect(rig.snap.played.map(\.file) == round)
        await rig.send(.play)
        #expect(rig.snap.played.isEmpty && rig.snap.tune?.file != round.last && rig.snap.queue.count == 3)
        await rig.close()
    }

    @Test func repeatOneAddsNothing() async throws {
        let rig = try await rig(4, repeat: .one)
        let round = list(rig)
        await finish(rig, 3)
        #expect(list(rig) == round && rig.snap.played.isEmpty && rig.snap.tune?.file == round[0])
        await rig.close()
    }

    @Test func aRestartStartsAfresh() async throws {
        let rig = try await rig(4)
        await finish(rig, 2)
        rig.make()
        await rig.send(.selectGenre(id: "jazz"))
        #expect(rig.snap.played.isEmpty)
        await rig.close()
    }

    @Test func aPlayedRowCanBeAimedAt() async throws {
        let rig = try await rig(4)
        await finish(rig, 2)
        let p0 = rig.snap.played[0]
        let info = try await rig.engine.shareInfo(for: TuneTarget(name: p0.name, index: 0, inPlayed: true)).get()
        #expect(info.name == p0.name)
        #expect(refusal(await rig.engine.setPinned(true, for: TuneTarget(name: p0.name, index: 5, inPlayed: true))) != nil)
        await rig.close()
    }

    @Test(arguments: [1, 2, 3] as [UInt64])
    func aSeededWalkForwardsBackAndForwards(seed: UInt64) async throws {
        let rig = try await rig(7, seed: seed)
        let round = list(rig)
        #expect(round.sorted() == rig.engine.keptNames().map(TuneFiles.stem))
        await finish(rig, 4)
        #expect(list(rig) == round)
        for _ in 0..<2 {
            rig.player.position = 0
            await rig.send(.refresh)
            await rig.send(.previous)
            #expect(list(rig) == round)
        }
        #expect(rig.snap.tune?.file == round[2])
        await rig.send(.playPlayed(index: 0, name: rig.snap.played[0].name))
        #expect(rig.snap.tune?.file == round[0] && list(rig) == round)
        await finish(rig, 5)
        #expect(rig.snap.tune?.file == round[5] && list(rig) == round)
        await rig.close()
    }
}
