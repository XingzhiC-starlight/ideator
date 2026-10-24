import XCTest
@testable import Ideator

final class SwipeTests: XCTestCase {
    private var tracker = SwipeTracker()

    private func feed(_ phase: NSEvent.Phase = [], momentum: NSEvent.Phase = [],
                      dx: CGFloat = 0, dy: CGFloat = 0, at time: TimeInterval = 0) -> SwipeTracker.Verdict {
        tracker.feed(phase: phase, momentumPhase: momentum, deltaX: dx, deltaY: dy, at: time)
    }

    func testAHorizontalSwipeFlipsOnceAndSwallowsTheRestOfTheGestureAndItsMomentum() {
        XCTAssertEqual(feed(.began, dx: -4), .consume, "the first movement locks the horizontal axis")
        XCTAssertEqual(feed(.changed, dx: -10), .consume, "14 points is short of a flip")
        XCTAssertEqual(feed(.changed, dx: -20), .flip(.next), "past 30 points, fingers moving left show the next card")
        XCTAssertEqual(feed(.changed, dx: -40), .consume, "the same swipe does not flip again")
        XCTAssertEqual(feed(.ended), .consume, "the end of the gesture is swallowed")
        XCTAssertEqual(feed(momentum: .began, dx: -30), .consume, "so is its inertia")
        XCTAssertEqual(feed(momentum: .changed, dx: -30), .consume, "all of it")
        XCTAssertEqual(feed(momentum: .ended), .consume, "to the last event")
    }

    func testFingersMovingRightShowThePreviousCard() {
        XCTAssertEqual(feed(.began, dx: 5), .consume, "the gesture starts")
        XCTAssertEqual(feed(.changed, dx: 40), .flip(.previous), "positive dx is previous")
    }

    func testAShortSwipeNeverFlips() {
        XCTAssertEqual(feed(.began, dx: -8), .consume, "the gesture starts")
        XCTAssertEqual(feed(.changed, dx: -8), .consume, "16 points")
        XCTAssertEqual(feed(.ended), .consume, "and ends without a flip")
        XCTAssertEqual(feed(momentum: .began, dx: -5), .consume, "its small momentum is still swallowed")
    }

    func testAVerticalGestureAlwaysPassesToTheText() {
        XCTAssertEqual(feed(.began, dy: 6), .pass, "vertical locks the axis")
        XCTAssertEqual(feed(.changed, dx: 60, dy: 4), .pass, "later sideways drift does not flip")
        XCTAssertEqual(feed(.ended), .pass, "the end passes")
        XCTAssertEqual(feed(momentum: .began, dy: 20), .pass, "and so does the inertia")
        XCTAssertEqual(feed(momentum: .ended), .pass, "to the last event")
    }

    func testTheAxisLocksOnTheFirstNonTrivialMovement() {
        XCTAssertEqual(feed(.began, dx: 0.3, dy: 0.2), .pass, "a tiny first movement decides nothing")
        XCTAssertEqual(feed(.changed, dx: 6, dy: 2), .consume, "the first real movement is horizontal")
        XCTAssertEqual(feed(.changed, dy: 50), .consume, "so a later vertical move does not unlock it")
    }

    func testANewGestureStartsFresh() {
        XCTAssertEqual(feed(.began, dx: -40), .flip(.next), "the first swipe flips")
        XCTAssertEqual(feed(.ended), .consume, "and ends")
        XCTAssertEqual(feed(.began, dy: 5), .pass, "the next gesture is vertical")
        XCTAssertEqual(feed(.ended), .pass, "and ends")
        XCTAssertEqual(feed(.began, dx: 40), .flip(.previous), "the third flips again")
    }

    func testMomentumOfAGestureWeNeverSawIsPassed() {
        XCTAssertEqual(feed(momentum: .changed, dx: -30), .pass, "nothing locked an axis, so the text keeps it")
    }

    func testAMouseWheelFlipsThenWaitsBeforeFlippingAgain() {
        XCTAssertEqual(feed(dx: -3, at: 10.0), .flip(.next), "a horizontal wheel click flips")
        XCTAssertEqual(feed(dx: -3, at: 10.1), .consume, "the next click inside the pause is swallowed")
        XCTAssertEqual(feed(dx: 3, at: 10.25), .consume, "in either direction")
        XCTAssertEqual(feed(dx: 3, at: 10.4), .flip(.previous), "after the pause it flips again")
    }

    func testAVerticalWheelPassesToTheText() {
        XCTAssertEqual(feed(dy: 3, at: 1), .pass, "vertical scrolls the text")
        XCTAssertEqual(feed(dx: 1, dy: 5, at: 2), .pass, "so does mostly vertical")
    }
}
