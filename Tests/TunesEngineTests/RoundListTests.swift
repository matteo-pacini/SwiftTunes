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

    @Test func aNewTuneJoinsTheEndAndNothingListedMoves() async throws {
        let rig = try await rig(5, ahead: 1)
        await finish(rig, 2)
        let before = list(rig)
        await rig.send(.setComposer(on: true))
        #expect(await rig.run { rig.snap.ready == 1 })
        await rig.send(.setComposer(on: false))
        let new = try #require(rig.snap.queue.last)
        #expect(new.new)
        #expect(list(rig) == before + [new.file])
        await rig.close()
    }

    @Test func aGenreWithNoTunesNumbersItsTunesInTheOrderMade() async throws {
        let rig = try await Rig(ahead: 2)
        await rig.send(.selectGenre(id: "jazz"))
        #expect(rig.snap.tune == nil && rig.snap.queue.isEmpty)
        await rig.send(.setComposer(on: true))
        var made: [String] = []
        /// Waits for the next finished tune: it is the last of the list and
        /// every tune before it keeps its place.
        func nextMade(sourceLocation: SourceLocation = #_sourceLocation) async throws {
            #expect(await rig.run { list(rig).count == made.count + 1 }, sourceLocation: sourceLocation)
            let now = list(rig)
            #expect(Array(now.prefix(made.count)) == made, sourceLocation: sourceLocation)
            let new = try #require(now.last, sourceLocation: sourceLocation)
            #expect(!made.contains(new), sourceLocation: sourceLocation)
            made.append(new)
        }
        try await nextMade()
        #expect(rig.snap.tune?.file == made[0] && rig.snap.played.isEmpty)
        try await nextMade()
        try await nextMade()
        #expect(rig.snap.tune?.file == made[0] && rig.snap.queue.map(\.file) == Array(made[1...]))
        await rig.send(.next)
        #expect(list(rig) == made && rig.snap.played.map(\.file) == [made[0]] && rig.snap.tune?.file == made[1])
        try await nextMade()
        await rig.send(.next)
        #expect(list(rig) == made && rig.snap.tune?.file == made[2])
        try await nextMade()
        await finish(rig)
        #expect(list(rig) == made && rig.snap.played.map(\.file) == Array(made[0...2]) && rig.snap.tune?.file == made[3])
        #expect(made.count == 5)
        await rig.send(.setComposer(on: false))
        await rig.close()
    }

    @Test func withNothingWaitingANewTunePlaysNextThenTheNextRound() async throws {
        let rig = try await rig(3, shuffle: false, ahead: 1)
        await finish(rig, 2)
        let round = list(rig)
        #expect(rig.snap.queue.isEmpty)
        await rig.send(.setComposer(on: true))
        #expect(await rig.run { rig.snap.ready == 1 })
        await rig.send(.setComposer(on: false))
        let new = try #require(rig.snap.queue.first)
        #expect(new.new && rig.snap.queue.count == 1)
        await finish(rig)
        #expect(rig.snap.tune?.file == new.file && list(rig) == round + [new.file])
        await finish(rig)
        #expect(rig.snap.played.isEmpty && rig.snap.tune?.file == round[0])
        await rig.close()
    }

    @Test func aNewTuneFinishedAfterARoundEndedWithRepeatOffPlays() async throws {
        let rig = try await rig(3, repeat: .off, ahead: 1)
        await finish(rig, 3)
        #expect(rig.snap.ended && rig.snap.tune == nil)
        await rig.send(.setComposer(on: true))
        #expect(await rig.run { rig.snap.tune?.new == true })
        #expect(!rig.snap.ended && rig.snap.player == .playing)
        await rig.close()
    }

    @Test func withRepeatOneANewTuneWaitsLast() async throws {
        let rig = try await rig(3, shuffle: false, repeat: .one, ahead: 1)
        let before = list(rig)
        await rig.send(.setComposer(on: true))
        #expect(await rig.run { rig.snap.ready == 1 && rig.snap.model.state == .idle })
        let new = try #require(rig.snap.queue.last)
        #expect(new.new && list(rig) == before + [new.file])
        await finish(rig)
        #expect(rig.snap.tune?.file == before[0] && rig.snap.ready == 1)
        await rig.close()
    }

    @Test(arguments: [true, false])
    func aShuffleChangeKeepsWaitingNewTunesLastInTheOrderMade(startShuffled: Bool) async throws {
        let rig = try await rig(6, shuffle: startShuffled, ahead: 2)
        await rig.send(.setComposer(on: true))
        #expect(await rig.run { rig.snap.ready == 1 })
        let first = try #require(rig.snap.queue.last)
        #expect(await rig.run { rig.snap.ready == 2 })
        await rig.send(.setComposer(on: false))
        let second = try #require(rig.snap.queue.last)
        #expect(first.new && second.new && first.file != second.file)
        let kept = Set(rig.snap.queue.dropLast(2).map(\.file))
        await rig.send(.setShuffle(on: !startShuffled))
        #expect(rig.snap.queue.suffix(2).map(\.file) == [first.file, second.file])
        #expect(Set(rig.snap.queue.dropLast(2).map(\.file)) == kept)
        await rig.close()
    }

    @Test func aNewRoundDrawnWhileNewTunesWaitPutsThemLast() async throws {
        let rig = try await rig(4, shuffle: true, ahead: 2)
        await rig.send(.setComposer(on: true))
        #expect(await rig.run { rig.snap.ready == 2 })
        await rig.send(.setComposer(on: false))
        let new = rig.snap.queue.filter(\.new).map(\.file)
        // No command draws a round while new tunes wait; the engine's own
        // draw is called to hold it to the rule all the same.
        rig.engine.newRound()
        rig.engine.changed()
        await rig.settle()
        #expect(rig.snap.queue.suffix(2).map(\.file) == new)
        #expect(rig.snap.queue.dropLast(2).allSatisfy { $0.kept })
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
        // A new tune made now joins the end; the tune put back stays first.
        await rig.send(.setComposer(on: true))
        #expect(await rig.run { rig.snap.ready == 1 })
        let new = try #require(rig.snap.queue.last)
        #expect(rig.snap.queue.first?.file == wasPlaying && new.new)
        #expect(list(rig) == round + [new.file])
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
