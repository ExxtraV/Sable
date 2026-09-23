import Foundation

/// How far the writing page can be zoomed, and how Command-scrolling a mouse wheel moves through that range.
enum ZoomSteps {
    static let range: ClosedRange<Double> = 0.65...2
    /// One wheel notch. Zoom lands on multiples of this, so the percentage stays a round number.
    static let perNotch = 0.05
    /// A fast spin reports several notches in one event; cap it so one flick can't jump the whole range.
    static let mostNotchesPerEvent = 3.0
    /// While the wheel keeps turning, the page is restyled at most this often. Each restyle lays out the whole
    /// document, so a fast spin applies the notches in between together instead of redrawing on every one.
    static let commitInterval: TimeInterval = 0.15

    static func clamped(_ zoom: Double) -> Double { min(range.upperBound, max(range.lowerBound, zoom)) }

    /// Command-scrolling zooms only with a notched mouse wheel. A trackpad (or any device with precise deltas)
    /// keeps scrolling, since pinching already zooms there and a held Command key shouldn't hijack a two-finger scroll.
    static func wheelZooms(command: Bool, preciseDeltas: Bool, deltaX: Double, deltaY: Double) -> Bool {
        command && !preciseDeltas && deltaY != 0 && abs(deltaY) >= abs(deltaX)
    }

    /// Whole notches toward zooming in: turning the wheel away from you zooms in, whatever the scroll direction setting.
    static func notches(deltaY: Double, directionInverted: Bool) -> Double {
        guard deltaY != 0 else { return 0 }
        let size = min(mostNotchesPerEvent, max(1, abs(deltaY).rounded()))
        return (deltaY > 0) != directionInverted ? size : -size
    }

    /// The zoom after `notches` from `zoom`, on the notch grid and inside the range.
    static func target(from zoom: Double, notches: Double) -> Double {
        clamped(((zoom + notches * perNotch) / perNotch).rounded() * perNotch)
    }

    /// How long to hold a wheel zoom before applying it, given the time since the last one was applied
    /// (never longer than one interval, even for an event stamped before that).
    static func commitDelay(sinceLastCommit elapsed: TimeInterval) -> TimeInterval {
        min(commitInterval, max(0, commitInterval - elapsed))
    }
}
