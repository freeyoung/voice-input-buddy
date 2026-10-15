import Testing
@testable import VoiceInputBuddy

@Suite("Circular navigation boundaries")
struct CircularNavigationBoundaryTests {
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
