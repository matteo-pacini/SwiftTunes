import Testing
import TunesContract
@testable import TunesPanel

@Suite("The volume slider")
struct VolumeSliderTests {
    @Test("a drag: each place while held, the last one final on release")
    func drag() {
        var v = VolumeSlider()
        v.report(0.3)
        v.began()
        #expect(v.set(0.42) == .setVolume(to: 0.42, dragging: true))
        #expect(v.set(0.5) == .setVolume(to: 0.5, dragging: true))
        #expect(v.ended() == .setVolume(to: 0.5, dragging: false))
    }

    @Test("a click on the track, editing reported first: the place, then final")
    func clickEditingFirst() {
        var v = VolumeSlider()
        v.report(0.3)
        v.began()
        #expect(v.set(0.8) == .setVolume(to: 0.8, dragging: true))
        #expect(v.ended() == .setVolume(to: 0.8, dragging: false))
        #expect(v.drawn(0.3) == 0.8)
    }

    @Test("a click on the track, the place reported first: final at once, nothing on release, never the snapshot's level")
    func clickPlaceFirst() {
        var v = VolumeSlider()
        v.report(0.3)
        #expect(v.set(0.8) == .setVolume(to: 0.8, dragging: false))
        v.began()
        #expect(v.drawn(0.3) == 0.8)
        #expect(v.ended() == nil)
        #expect(v.drawn(0.3) == 0.8)
    }

    @Test("a press without movement sends nothing")
    func pressOnly() {
        var v = VolumeSlider()
        v.report(0.3)
        v.began()
        #expect(v.ended() == nil)
        #expect(v.drawn(0.3) == 0.3)
    }

    @Test("a release without a hold sends nothing")
    func endedAlone() {
        var v = VolumeSlider()
        v.report(0.3)
        #expect(v.ended() == nil)
    }

    @Test("a keyboard or accessibility step: final at once")
    func step() {
        var v = VolumeSlider()
        v.report(0.3)
        #expect(v.set(0.4) == .setVolume(to: 0.4, dragging: false))
        #expect(v.drawn(0.3) == 0.4)
        v.report(0.4)
        #expect(v.drawn(0.4) == 0.4)
    }

    @Test("a place that is not finite sends nothing and moves nothing")
    func notFinite() {
        var v = VolumeSlider()
        v.began()
        #expect(v.set(.nan) == nil)
        #expect(v.ended() == nil)
        #expect(v.drawn(0.3) == 0.3)
    }

    @Test("while held it draws its own place, whatever the snapshots say")
    func heldIgnoresSnapshots() {
        var v = VolumeSlider()
        v.report(0.3)
        v.began()
        _ = v.set(0.6)
        v.report(0.6)
        #expect(v.drawn(0.6) == 0.6)
        _ = v.set(0.7)
        v.report(0.65)
        #expect(v.drawn(0.65) == 0.7)
    }

    @Test("after release: its place until a snapshot equal to the hundredth, then the snapshot's")
    func afterRelease() {
        var v = VolumeSlider()
        v.report(0.3)
        v.began()
        _ = v.set(0.5)
        _ = v.set(0.704)
        _ = v.ended()
        v.report(0.5)
        #expect(v.drawn(0.5) == 0.704)
        v.report(0.7)
        #expect(v.drawn(0.7) == 0.7)
        v.report(0.2)
        #expect(v.drawn(0.2) == 0.2)
    }

    @Test("after release: the snapshot already equal to the place lets it go, since no new one comes")
    func releaseAlreadyReported() {
        var v = VolumeSlider()
        v.report(0.3)
        v.began()
        _ = v.set(0.5)
        v.report(0.5)
        _ = v.ended()
        v.report(0.9)
        #expect(v.drawn(0.9) == 0.9)
    }
}
