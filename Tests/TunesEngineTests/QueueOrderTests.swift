import Foundation
import Testing
import TunesContract
@testable import TunesEngine
import TunesFakes
import TunesRules

/// The queue in true play order, the round drawn once, through the engine
/// with its seeded random source.
@Suite(.serialized, .timeLimit(.minutes(1))) struct QueueOrderTests {
    func rig(_ count: Int, shuffle: Bool, repeat mode: RepeatMode = .all, seed: UInt64 = 11) async throws -> (Rig, [String]) {
        let rig = try await Rig(seed: seed)
        for d in 1...count { try rig.keptTune("Jazz", day: d) }
        rig.make()
        await rig.send(.setShuffle(on: shuffle))
        await rig.send(.setRepeat(mode))
        await rig.send(.selectGenre(id: "jazz"))
        return (rig, rig.tunes("Jazz").map(TuneFiles.stem))
    }

    /// Plays `n` tunes to their end, checking at each step that the queue
    /// told the truth about what came next. The files played, in order.
    func play(_ rig: Rig, _ n: Int, sourceLocation: SourceLocation = #_sourceLocation) async -> [String] {
        var out: [String] = []
        for _ in 0..<n {
            guard let now = rig.snap.tune?.file else { break }
            out.append(now)
            let s = rig.snap
            #expect(s.roundLeft == s.queue.filter(\.kept).count, sourceLocation: sourceLocation)
            // The queue ends with the round: on its last tune it is empty,
            // and the next round's first is not the tune that ends this one.
            let promised = s.queue.first?.file
            rig.player.finish()
            await rig.settle()
            if let promised {
                #expect(rig.snap.tune?.file == promised, "the queue said \(promised) was next", sourceLocation: sourceLocation)
            } else {
                #expect(s.roundLeft == 0, sourceLocation: sourceLocation)
                #expect(rig.snap.tune?.file != now || s.keptTotal == 1, sourceLocation: sourceLocation)
            }
        }
        return out
    }

    @Test(arguments: [1, 2, 3] as [UInt64])
    func shuffledRoundsPlayEachTuneOnceAndNeverTwiceInARow(seed: UInt64) async throws {
        let (rig, k) = try await rig(6, shuffle: true, seed: seed)
        #expect(rig.snap.queue.count == 5 && rig.snap.roundLeft == 5)
        let got = await play(rig, 60)
        #expect(got.count == 60)
        for i in stride(from: 0, to: 60, by: 6) {
            #expect(Array(got[i..<(i + 6)]).sorted() == k, "round \(i / 6)")
        }
        #expect(zip(got, got.dropFirst()).allSatisfy { $0 != $1 })
        #expect(Set(stride(from: 0, to: 60, by: 6).map { got[$0..<($0 + 6)].joined() }).count > 1)
        await rig.close()
    }

    @Test func shuffleOffPlaysTheOrderMadeRoundAfterRound() async throws {
        let (rig, k) = try await rig(4, shuffle: false)
        #expect(rig.snap.queue.map(\.file) == Array(k[1...]))
        #expect(await play(rig, 10) == Array((k + k + k).prefix(10)))
        await rig.close()
    }

    @Test func repeatOffEndsTheRoundAndANewOneNeverStartsWithTheLast() async throws {
        let (rig, k) = try await rig(5, shuffle: true, repeat: .off)
        let got = await play(rig, 5)
        #expect(got.sorted() == k)
        #expect(rig.snap.ended && rig.snap.queue.isEmpty && rig.snap.roundLeft == 0)
        await rig.send(.play)
        #expect(rig.snap.tune?.file != got.last)
        #expect(rig.snap.queue.count == 4)
        await rig.close()
    }

    @Test func turningShuffleOnRedrawsWhatIsLeft() async throws {
        let (rig, k) = try await rig(6, shuffle: false)
        let first = await play(rig, 2)
        let left = rig.snap.queue.map(\.file)
        await rig.send(.setShuffle(on: true))
        #expect(rig.snap.queue.map(\.file).sorted() == left.sorted())
        let rest = await play(rig, 4)
        #expect((first + rest).sorted() == k)
        await rig.close()
    }

    @Test func turningShuffleOffFollowsTheOrderMadeFromThePlayingTune() async throws {
        let (rig, k) = try await rig(6, shuffle: true)
        let first = await play(rig, 2)
        await rig.send(.setShuffle(on: false))
        let playing = try #require(rig.snap.tune?.file)
        let left = k.filter { !first.contains($0) && $0 != playing }
        #expect(rig.snap.queue.map(\.file) == Rounds.made(left, after: playing))
        await rig.close()
    }

    @Test func aTuneThatBecomesKeptJoinsTheEnd() async throws {
        let (rig, k) = try await rig(3, shuffle: false)
        // A tune appears in the folder mid-round: it joins the end of the order.
        let added = try rig.keptTune("Jazz", day: 20)
        await rig.send(.refresh)
        #expect(rig.snap.queue.map(\.file) == Array(k[1...]) + [TuneFiles.stem(added.lastPathComponent)])
        await rig.close()
    }

    @Test func aNewTunePlaysFirstThenBelongsToTheNextRound() async throws {
        let rig = try await Rig(ahead: 1)
        for d in 1...3 { try rig.keptTune("Jazz", day: d) }
        rig.make()
        await rig.send(.setShuffle(on: false))
        await rig.send(.selectGenre(id: "jazz"))
        let k = rig.tunes("Jazz").map(TuneFiles.stem)
        await rig.send(.setComposer(on: true))
        #expect(await rig.run { rig.snap.ready == 1 && rig.snap.model.state == .idle })
        await rig.send(.setComposer(on: false))
        let new = try #require(rig.snap.queue.first)
        #expect(new.new && rig.snap.queue.dropFirst().map(\.file) == Array(k[1...]))
        let got = await play(rig, 7)
        // The new tune, then the rest of this round, then a round of all four
        // in the order made with the once-new tune last.
        #expect(got == [k[0], new.file, k[1], k[2], k[0], k[1], k[2]])
        #expect(await play(rig, 1) == [new.file])
        await rig.close()
    }

    @Test func commandsByIndexAndNameAcrossTheWholeQueue() async throws {
        let (rig, _) = try await rig(9, shuffle: true)
        #expect(rig.snap.queue.count == 8)
        let row5 = rig.snap.queue[5]
        await rig.send(.scrapQueued(index: 5, name: rig.snap.queue[4].name))
        #expect(rig.snap.queue.count == 8)
        await rig.send(.scrapQueued(index: 5, name: row5.name))
        #expect(rig.snap.queue.count == 7 && !rig.snap.queue.contains { $0.file == row5.file })
        let row6 = rig.snap.queue[6]
        await rig.send(.playQueued(index: 6, name: row6.name))
        #expect(rig.snap.tune?.file == row6.file)
        #expect(rig.snap.queue.count == 6 && !rig.snap.queue.contains { $0.file == row6.file })
        await rig.close()
    }
}
