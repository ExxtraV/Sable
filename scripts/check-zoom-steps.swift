import Foundation

@main enum ZoomStepChecks {
    static func main() {
        func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

        precondition(ZoomSteps.clamped(5) == 2 && ZoomSteps.clamped(0.1) == 0.65 && ZoomSteps.clamped(1.3) == 1.3, "Zoom stays within 65%–200%")

        precondition(ZoomSteps.wheelZooms(command: true, preciseDeltas: false, deltaX: 0, deltaY: 1), "Command plus a wheel notch zooms")
        precondition(!ZoomSteps.wheelZooms(command: false, preciseDeltas: false, deltaX: 0, deltaY: 1), "A plain wheel scrolls")
        precondition(!ZoomSteps.wheelZooms(command: true, preciseDeltas: true, deltaX: 0, deltaY: 12), "A trackpad keeps scrolling with Command held")
        precondition(!ZoomSteps.wheelZooms(command: true, preciseDeltas: false, deltaX: 2, deltaY: 1), "A sideways wheel doesn't zoom")
        precondition(!ZoomSteps.wheelZooms(command: true, preciseDeltas: false, deltaX: 0, deltaY: 0), "An empty event doesn't zoom")

        precondition(ZoomSteps.notches(deltaY: 1, directionInverted: false) == 1, "Wheel away from you zooms in")
        precondition(ZoomSteps.notches(deltaY: -1, directionInverted: true) == 1, "…with natural scrolling too")
        precondition(ZoomSteps.notches(deltaY: -1, directionInverted: false) == -1 && ZoomSteps.notches(deltaY: 1, directionInverted: true) == -1, "Wheel toward you zooms out")
        precondition(ZoomSteps.notches(deltaY: 0.2, directionInverted: false) == 1, "A slow notch still counts as a notch")
        precondition(ZoomSteps.notches(deltaY: 2.4, directionInverted: false) == 2, "A faster spin counts its notches")
        precondition(ZoomSteps.notches(deltaY: -40, directionInverted: false) == -ZoomSteps.mostNotchesPerEvent, "One flick is capped")
        precondition(ZoomSteps.notches(deltaY: 0, directionInverted: false) == 0)

        precondition(close(ZoomSteps.target(from: 1, notches: 1), 1.05) && close(ZoomSteps.target(from: 1, notches: -2), 0.9), "One notch is 5%")
        precondition(close(ZoomSteps.target(from: 1.07, notches: 1), 1.1), "A pinched zoom snaps back to round percentages")
        precondition(ZoomSteps.target(from: 1.98, notches: 3) == 2 && ZoomSteps.target(from: 0.67, notches: -3) == 0.65, "The wheel stops at the ends")
        var zoom = 1.0
        for _ in 0..<200 { zoom = ZoomSteps.target(from: zoom, notches: 1) }
        precondition(zoom == 2, "Spinning past the top doesn't overshoot")
        zoom = ZoomSteps.target(from: zoom, notches: -1)
        precondition(close(zoom, 1.95), "…and one notch back comes straight down, with nothing to unwind")
        for _ in 0..<4 { zoom = ZoomSteps.target(from: zoom, notches: 1) }
        for _ in 0..<4 { zoom = ZoomSteps.target(from: zoom, notches: -1) }
        precondition(close(zoom, 1.8), "In and out by the same notches returns to the same zoom (no drift)")
        let grid = stride(from: 0.0, to: 20, by: 1).map { ZoomSteps.target(from: 0.65, notches: $0) }
        precondition(grid.allSatisfy { close(($0 / ZoomSteps.perNotch).rounded() * ZoomSteps.perNotch, $0) }, "Every wheel zoom is a whole percentage step")

        precondition(ZoomSteps.commitDelay(sinceLastCommit: 10) == 0, "The first notch applies at once")
        precondition(close(ZoomSteps.commitDelay(sinceLastCommit: 0.05), ZoomSteps.commitInterval - 0.05), "A fast spin waits for the next restyle")
        precondition(ZoomSteps.commitDelay(sinceLastCommit: ZoomSteps.commitInterval) == 0)
        precondition(ZoomSteps.commitDelay(sinceLastCommit: -5) == ZoomSteps.commitInterval, "An event stamped before the last zoom waits no longer than usual")

        print("Zoom step checks passed.")
    }
}
