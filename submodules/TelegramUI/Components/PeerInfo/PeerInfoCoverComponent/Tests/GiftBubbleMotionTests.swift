import XCTest
@testable import PeerInfoCoverComponent

final class GiftBubbleMotionTests: XCTestCase {
    func testEveryBubbleMovesWithoutChangingItsAnchorAtStartup() {
        for index in 0 ..< 6 {
            XCTAssertEqual(giftBubbleMotionOffset(phase: 0.0, index: index), .zero)
            let offset = giftBubbleMotionOffset(phase: 0.125, index: index)
            XCTAssertGreaterThan(hypot(offset.x, offset.y), 2.0)
        }
    }

    func testLoopHasNoPositionOrVelocityJump() {
        let step = 0.00001
        for index in 0 ..< 6 {
            let start = giftBubbleMotionOffset(phase: 0.0, index: index)
            let end = giftBubbleMotionOffset(phase: 1.0, index: index)
            XCTAssertEqual(start.x, end.x, accuracy: 0.000001)
            XCTAssertEqual(start.y, end.y, accuracy: 0.000001)
            let before = giftBubbleMotionOffset(phase: 1.0 - step, index: index)
            let after = giftBubbleMotionOffset(phase: step, index: index)
            XCTAssertEqual((end.x - before.x) / step, (after.x - start.x) / step, accuracy: 0.01)
            XCTAssertEqual((end.y - before.y) / step, (after.y - start.y) / step, accuracy: 0.01)
        }
    }

    func testMotionStaysInsideTheReservedMarginAcrossManyCycles() {
        for index in 0 ..< 6 {
            for sample in 0 ... 2400 {
                let offset = giftBubbleMotionOffset(phase: Double(sample) / 120.0, index: index)
                XCTAssertLessThanOrEqual(abs(offset.x), 7.000001)
                XCTAssertLessThanOrEqual(abs(offset.y), 5.000001)
            }
        }
    }

    func testDepthVariationDoesNotMoveEveryBubbleInLockstep() {
        let near = giftBubbleMotionOffset(phase: 0.125, index: 2)
        let far = giftBubbleMotionOffset(phase: 0.125, index: 0)
        XCTAssertGreaterThan(hypot(near.x - far.x, near.y - far.y), 0.1)
    }
}
