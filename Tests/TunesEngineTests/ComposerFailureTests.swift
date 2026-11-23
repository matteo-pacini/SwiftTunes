import Foundation
import Testing
import TunesContract
@testable import TunesEngine
import TunesFakes
import TunesRules

@Suite(.serialized) struct ComposerFailureTests {
    func composing(_ rig: Rig) async {
        await rig.send(.selectGenre(id: "jazz"))
        await rig.send(.setComposer(on: true))
    }

    @Test func aSilentPlanIsWrittenAgain() async throws {
        let rig = try await Rig()
        await rig.ace.set(kinds: [.silent, .normal])
        await composing(rig)
        #expect(await rig.run { rig.snap.tune != nil })
        #expect(rig.snapshots.contains { $0.model.silenceS == 6 && $0.model.state == .writing })
        #expect(await rig.ace.lmCount >= 2)
        #expect(rig.snap.model.silenceS == nil && rig.snap.model.failures == 0)
        await rig.close()
    }

    @Test func theThirdSilentPlanIsAFailureThenARetry() async throws {
        let rig = try await Rig()
        await rig.ace.set(kinds: [.silent, .silent, .silent])
        await composing(rig)
        #expect(await rig.run { rig.snap.model.state == .failed })
        let m = rig.snap.model
        #expect(m.detail == "3 plans in a row had long silences")
        #expect(m.failures == 1 && m.retryAt == rig.clock.now + 3)
        #expect(rig.launcher.running == 0)
        #expect(rig.snap.job == nil)
        // The retry comes by itself and this time the plans are fine.
        #expect(await rig.run { rig.snap.tune != nil })
        #expect(rig.snap.model.failures == 0)
        await rig.close()
    }

    @Test func secondFailureWaitsThirtySeconds() async throws {
        let rig = try await Rig()
        await rig.ace.set(kinds: [.fail, .fail])
        await composing(rig)
        #expect(await rig.run { rig.snap.model.failures == 2 })
        #expect(rig.snap.model.detail == "the song job failed")
        #expect(rig.snap.model.retryAt == rig.clock.now + 30)
        await rig.close()
    }

    @Test func tryNowRetriesAtOnce() async throws {
        let rig = try await Rig()
        await rig.ace.set(kinds: [.fail])
        await composing(rig)
        #expect(await rig.run { rig.snap.model.state == .failed })
        let launches = rig.launcher.launches.count
        await rig.send(.retry)
        #expect(rig.launcher.launches.count == launches + 1)
        #expect(rig.snap.model.retryAt == nil)
        #expect(await rig.run { rig.snap.tune != nil })
        await rig.close()
    }

    @Test func retryIsIgnoredUnlessFailed() async throws {
        let rig = try await Rig()
        await composing(rig)
        let before = rig.snapshots.count
        await rig.send(.retry)
        #expect(rig.snapshots.count == before)
        await rig.close()
    }

    @Test func theLoudnessBackstop() async throws {
        let rig = try await Rig()
        await rig.ace.set(kinds: [.quiet])
        await composing(rig)
        #expect(await rig.run { rig.snap.model.state == .failed })
        #expect(rig.snap.model.detail == "the rendered tune is silent for 6 s in the middle")
        #expect(rig.tunes("Jazz").isEmpty)
        #expect(Files.list(rig.paths.caches.appending(path: "work")).isEmpty)
        await rig.close()
    }

    @Test func aCrashingServer() async throws {
        let rig = try await Rig()
        await rig.ace.set(kinds: [.exit])
        let launcher = rig.launcher
        await rig.ace.set(onCrash: { await launcher.crash() })
        await composing(rig)
        #expect(await rig.run { rig.snap.model.state == .failed })
        #expect(rig.snap.model.detail == "the model server exited (status 134): GGML_ASSERT failed: a fake crash")
        #expect(rig.launcher.running == 0)
        await rig.close()
    }

    @Test func noMetalDevice() async throws {
        let rig = try await Rig()
        rig.launcher.noMetal = true
        rig.launcher.deviceLine = nil
        await composing(rig)
        #expect(rig.snap.model.state == .noDevice)
        #expect(rig.snap.model.detail == "the server offers only BLAS CPU")
        #expect(rig.snap.model.retryAt == nil)
        // No retry by itself.
        #expect(rig.clock.pending == 0 || !rig.clock.timers.contains { !$0.cancelled && $0.due > rig.clock.now })
        await rig.close()
    }

    @Test func listeningWithoutAMetalDevice() async throws {
        let rig = try await Rig()
        rig.launcher.deviceLine = nil
        await composing(rig)
        #expect(rig.snap.model.state == .noDevice)
        #expect(rig.snap.model.detail == "the server listed no MTL0")
        #expect(rig.launcher.running == 0)
        await rig.close()
    }

    @Test func aServerThatNeverStarts() async throws {
        let rig = try await Rig()
        await rig.ace.set(loadingHealth: 100_000)
        await composing(rig)
        #expect(await rig.run { rig.snap.model.state == .failed })
        #expect(rig.snap.model.detail == "the model server did not start in time")
        #expect(rig.clock.now == Rig.start + 120)
        #expect(rig.launcher.running == 0)
        await rig.close()
    }

    @Test func holdsBeforeAJobAndLiftByThemselves() async throws {
        let rig = try await Rig()
        rig.holds.hold = .power
        await composing(rig)
        #expect(rig.snap.model.state == .heldPower)
        #expect(rig.launcher.launches.isEmpty)
        rig.holds.hold = .heat
        #expect(await rig.run { rig.snap.model.state == .heldHeat })
        #expect(rig.clock.now == Rig.start + 30)
        rig.holds.hold = nil
        #expect(await rig.run { rig.snap.tune != nil })
        #expect(rig.snap.composing)
        await rig.close()
    }

    @Test func aHoldDuringAJobCancelsItAndStopsTheServer() async throws {
        let rig = try await Rig()
        await rig.ace.set(runningPolls: 100)
        await composing(rig)
        #expect(await rig.run { rig.snap.model.state == .writing })
        rig.holds.hold = .heat
        #expect(await rig.run { rig.snap.model.state == .heldHeat })
        #expect(rig.clock.now == Rig.start + 10)
        #expect(rig.snap.job == nil && rig.launcher.running == 0)
        #expect(await rig.ace.cancelled.count == 1)
        await rig.close()
    }

    @Test func memoryPressureDuringAJobDoesNotHoldIt() async throws {
        let rig = try await Rig()
        await composing(rig)
        #expect(await rig.run { rig.snap.model.state == .writing })
        rig.holds.hold = .memory
        // The job finishes; the next one waits for memory.
        #expect(await rig.run { rig.snap.model.state == .heldMemory })
        #expect(rig.tunes("Jazz").count == 1 && rig.snap.tune != nil)
        #expect(await rig.ace.cancelled.isEmpty)
        await rig.close()
    }

    @Test func scrapTheJob() async throws {
        let rig = try await Rig()
        await rig.ace.set(runningPolls: 100)
        await composing(rig)
        #expect(await rig.run { rig.snap.model.state == .writing })
        await rig.send(.scrapJob)
        #expect(await rig.ace.cancelled.count == 1)
        // Another one starts at once.
        #expect(rig.snap.job?.stage == .writing)
        #expect(await rig.ace.lmCount == 2)
        await rig.close()
    }

    @Test func composerOffStopsEverything() async throws {
        let rig = try await Rig()
        await rig.ace.set(runningPolls: 100)
        await composing(rig)
        #expect(await rig.run { rig.snap.model.state == .writing })
        await rig.send(.setComposer(on: false))
        #expect(rig.snap.model.state == .unloaded && rig.snap.job == nil && !rig.snap.composing)
        #expect(rig.launcher.running == 0)
        await rig.close()
    }

    @Test func composerNeedsSetupAndAGenre() async throws {
        let rig = try await Rig(ready: false)
        await rig.send(.setComposer(on: true))
        #expect(!rig.snap.composing)
        await rig.send(.selectGenre(id: "jazz"))
        await rig.send(.setComposer(on: true))
        #expect(!rig.snap.composing)
        await rig.close()
    }
}
