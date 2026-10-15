import Testing
@testable import VoiceInputBuddy

@Suite("Circular navigation boundaries")
struct CircularNavigationBoundaryTests {
    @Test func fastMotionRetainsOnlyABoundedRemainder() {
        var accumulator = AppleRemoteCircularNavigationAccumulator()
        #expect(accumulator.consume(1e300) == 3)
        #expect(accumulator.pendingPixels <= 2 * AppleRemoteCircularNavigationAccumulator.stepThreshold)
        #expect(accumulator.consume(1) == 2)
        #expect(accumulator.consume(1) == 0)
        #expect(accumulator.consume(-18) == -1)
        accumulator.reset()
        #expect(accumulator.pendingPixels == 0)
    }

    @Test func invalidAndHugeMotionCannotTrapIntegerConversion() {
        var accumulator = AppleRemoteCircularNavigationAccumulator()
        #expect(accumulator.consume(9) == 0)
        for value in [Double.nan, .infinity, -.infinity] {
            #expect(accumulator.consume(value) == 0)
            #expect(accumulator.pendingPixels == 9)
        }
        #expect(accumulator.consume(9) == 1)
        #expect(accumulator.consume(Double.greatestFiniteMagnitude) == 3)
        accumulator.reset()
        #expect(accumulator.consume(-Double.greatestFiniteMagnitude) == -3)
    }
}
