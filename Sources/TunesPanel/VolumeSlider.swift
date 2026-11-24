import TunesContract

/// The volume slider's own state: the place it draws and the commands it
/// sends, from the slider's events and the levels the engine reports. It never
/// sends a level taken from a snapshot. The events may come in either order
/// for a click on the track (the place before or after `began()`), and a
/// keyboard or accessibility step comes as a `set` with no `began()`.
public struct VolumeSlider: Sendable, Equatable {
    var editing = false
    /// The slider's own place, drawn while held and after release until a
    /// snapshot reports it.
    var place: Double?
    var placeSetInHold = false
    /// The last level a snapshot reported.
    var reported: Double?

    public init() {}

    /// The pointer took hold of the slider.
    public mutating func began() {
        editing = true
        placeSetInHold = false
    }

    /// The slider moved to `fraction`: the command for it, with `dragging`
    /// true while the pointer holds the slider.
    public mutating func set(_ fraction: Double) -> Command? {
        guard let command = Decide.volume(fraction: fraction, dragging: editing) else { return nil }
        place = fraction
        placeSetInHold = editing
        return command
    }

    /// The pointer let go: the last place set during this hold, final, or nil
    /// when none was set.
    public mutating func ended() -> Command? {
        defer {
            editing = false
            placeSetInHold = false
            // The engine sends no snapshot for a level it already has, so one
            // reported during the hold may be the last.
            if let r = reported { report(r) }
        }
        guard editing, placeSetInHold, let place else { return nil }
        return Decide.volume(fraction: place, dragging: false)
    }

    /// A snapshot reported `level`.
    public mutating func report(_ level: Double) {
        reported = level
        if !editing, let p = place, Self.hundredths(p) == Self.hundredths(level) { place = nil }
    }

    /// What the slider draws, given the snapshot's `level`.
    public func drawn(_ level: Double) -> Double { place ?? level }

    private static func hundredths(_ x: Double) -> Double { (x * 100).rounded() }
}
