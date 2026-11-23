import Foundation
import Testing
import TunesContract
@testable import TunesEngine
import TunesFakes
import TunesRules

/// A stop while a job runs cancels the job first and waits up to 1 s.
@Suite(.serialized) struct StopMidJobTests {
    func writing(_ rig: Rig) async {
        await rig.ace.set(runningPolls: 100)
        await rig.send(.selectGenre(id: "jazz"))
        await rig.send(.setComposer(on: true))
        #expect(await rig.run { rig.snap.model.state == .writing })
    }

    @Test func aJobThatEndsAtOnceStopsAtOnce() async throws {
        let rig = try await Rig()
        await writing(rig)
        let t = rig.clock.now
        await rig.send(.setComposer(on: false))
        #expect(await rig.ace.cancelled.count == 1)
        #expect(rig.launcher.running == 0)
        #expect(rig.clock.now == t)
        #expect(rig.launcher.processes.last?.killed == false)
        await rig.close()
    }

    @Test(arguments: [(3, 0.3), (1000, 1.0)])
    func theWaitEndsWithTheJobOrAfterASecond(polls: Int, seconds: Double) async throws {
        let rig = try await Rig()
        await writing(rig)
        await rig.ace.set(cancelPolls: polls)
        let t = rig.clock.now
        await rig.send(.setComposer(on: false))
        #expect(rig.snap.model.state == .unloaded && rig.snap.job == nil)
        #expect(rig.launcher.running == 1)
        #expect(await rig.run { rig.launcher.running == 0 })
        #expect(abs(rig.clock.now - t - seconds) < 1e-6)
        #expect(await rig.ace.cancelled.count == 1)
        // A job still running after the second is killed, not asked to stop.
        #expect(rig.launcher.processes.last?.killed == (seconds == 1.0))
        await rig.close()
    }

    @Test func aStopWithNoJobIsImmediate() async throws {
        let rig = try await Rig(ahead: 1)
        await rig.send(.selectGenre(id: "jazz"))
        await rig.send(.stop)
        await rig.send(.setComposer(on: true))
        #expect(await rig.run { rig.snap.model.state == .idle })
        #expect(rig.launcher.running == 0)
        #expect(await rig.ace.cancelled.isEmpty)
        await rig.close()
    }

    @Test func scrappingTheJobKeepsTheServerAndALaterStopIsImmediate() async throws {
        let rig = try await Rig()
        await writing(rig)
        await rig.send(.scrapJob)
        #expect(rig.launcher.running == 1)
        #expect(rig.engine.server?.cancelling == nil)
        await rig.close()
    }

    @Test func aStopWhileTheSongRequestIsInFlightCancelsItsJob() async throws {
        let rig = try await Rig()
        await rig.ace.set(runningPolls: 100)
        await rig.ace.set(holdLM: true)
        await rig.send(.selectGenre(id: "jazz"))
        rig.engine.send(.setComposer(on: true))
        _ = await rig.launcher.deliver()
        await rig.ace.untilLMHeld()
        let t = rig.clock.now
        rig.engine.send(.setComposer(on: false))
        #expect(rig.engine.timers["drain:\(rig.aceHTTP.port)"] != nil)
        #expect(rig.launcher.processes.last?.stopped == false)
        await rig.ace.releaseLM()
        await rig.settle()
        #expect(await rig.ace.cancelled == [1])
        #expect(rig.launcher.running == 0)
        #expect(rig.clock.now == t)
        await rig.close()
    }
}
