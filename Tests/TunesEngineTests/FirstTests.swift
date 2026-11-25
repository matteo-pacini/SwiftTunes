import Foundation
import Testing
import TunesContract
@testable import TunesEngine
import TunesFakes
import TunesRules

@Suite(.serialized) struct FirstSnapshotTests {
    @Test func firstSnapshotReflectsTheFilesAndPlaysNothing() async throws {
        let rig = try await Rig(ready: false)
        try rig.keptTune("Jazz", day: 1)
        rig.make()
        let s = rig.snap
        #expect(s.version == 1)
        #expect(s.setup == .missing)
        #expect(s.download == nil)
        #expect(s.genres == [GenreSummary(id: "jazz", name: "Jazz", kept: 1), GenreSummary(id: "lofi", name: "Lo-fi", kept: 0)])
        #expect(s.genre == nil && s.player == .none && !s.stopped && s.tune == nil && s.queue.isEmpty)
        #expect(s.need.downloadBytes == rig.modelFiles.values.reduce(0) { $0 + Int64($1.count) })
        #expect(s.need.ramBytes == 8_589_934_592)
        #expect(s.model.state == .unloaded && s.model.device == "Metal" && s.model.ramFreeBytes == nil)
        #expect(!s.shuffle && s.repeat == .all && s.keep == 50 && s.ahead == 2)
        #expect(s.error == nil)
        #expect(Files.read(rig.paths.support.appending(path: "genres.json")) == Rig.genresText)
        #expect(rig.player.calls.isEmpty)
        await rig.close()
    }

    @Test(arguments: [(nil, false), (#"{"repeat": "all"}"#, false), (#"{"shuffle": true}"#, true)] as [(String?, Bool)])
    func shuffleIsWhatTheStateFileSaysOrOff(state: String?, want: Bool) async throws {
        let rig = try await Rig()
        if let state {
            try Files.makeDirectory(rig.paths.support)
            try Data(state.utf8).write(to: rig.paths.support.appending(path: "state.json"))
        }
        rig.make()
        #expect(rig.snap.shuffle == want)
        await rig.close()
    }

    @Test func aFirstRoundOnANewInstallationPlaysInTheOrderMade() async throws {
        let rig = try await Rig()
        for d in 1...4 { try rig.keptTune("Jazz", day: d) }
        rig.make()
        await rig.send(.selectGenre(id: "jazz"))
        let k = rig.tunes("Jazz").map(TuneFiles.stem)
        #expect(rig.snap.tune?.file == k[0])
        #expect(rig.snap.queue.map(\.file) == Array(k[1...]))
        await rig.close()
    }

    @Test func suggestedNamesComeFromTheGenresWords() async throws {
        let rig = try await Rig()
        #expect(rig.engine.suggestTuneName() == "")
        await rig.send(.selectGenre(id: "jazz"))
        let names = (0..<20).map { _ in rig.engine.suggestTuneName() }
        let allowed = Set(["Blue", "Smoky"].flatMap { m in ["Avenue", "Lamp"].map { "\(m) \($0)" } })
        #expect(names.allSatisfy(allowed.contains))
        #expect(Set(names).count > 1)
        await rig.close()
    }
}
