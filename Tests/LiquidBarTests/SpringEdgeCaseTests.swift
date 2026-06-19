import Testing
@testable import LiquidBar

@Suite("Spring Physics Edge Cases")
struct SpringEdgeCaseTests {
    // MARK: - Negative Displacement

    @Test func testSpringNegativeDisplacement() {
        var spring = SpringState(current: 200, target: 50)
        let dt: Float = 1.0 / 60.0

        for _ in 0..<120 {
            _ = spring.tick(stiffness: SpringConstants.gapStiffness, damping: SpringConstants.gapDamping, dt: dt)
        }

        #expect(abs(spring.current - spring.target) < SpringConstants.positionThreshold)
    }

    // MARK: - Zero Displacement

    @Test func testSpringZeroDisplacement() {
        var spring = SpringState(current: 100, target: 100, velocity: 0)
        let animating = spring.tick(stiffness: SpringConstants.gapStiffness, damping: SpringConstants.gapDamping, dt: 1.0 / 60.0)
        #expect(animating == false)
        #expect(spring.current == 100)
    }

    // MARK: - Large Displacement

    @Test func testSpringLargeDisplacement() {
        var spring = SpringState(current: 0, target: 10000)
        let dt: Float = 1.0 / 60.0

        for _ in 0..<600 { // 10 seconds at 60fps
            _ = spring.tick(stiffness: SpringConstants.gapStiffness, damping: SpringConstants.gapDamping, dt: dt)
        }

        #expect(spring.current.isFinite)
        #expect(abs(spring.current - spring.target) < SpringConstants.positionThreshold)
    }

    // MARK: - Initial Velocity

    @Test func testSpringWithInitialVelocity() {
        var spring = SpringState(current: 100, target: 100, velocity: 500)
        let dt: Float = 1.0 / 60.0

        // Should overshoot due to initial velocity then return
        var maxValue: Float = 100
        for _ in 0..<120 {
            _ = spring.tick(stiffness: SpringConstants.gapStiffness, damping: SpringConstants.gapDamping, dt: dt)
            maxValue = max(maxValue, spring.current)
        }

        #expect(maxValue > 100) // Should overshoot
        #expect(abs(spring.current - spring.target) < SpringConstants.positionThreshold)
    }

    // MARK: - Multiple Targets

    @Test func testSpringTargetChange() {
        var spring = SpringState(current: 0, target: 100)
        let dt: Float = 1.0 / 60.0

        // Tick halfway
        for _ in 0..<30 {
            _ = spring.tick(stiffness: SpringConstants.gapStiffness, damping: SpringConstants.gapDamping, dt: dt)
        }

        // Change target
        spring.target = 200

        // Should converge to new target
        for _ in 0..<200 {
            _ = spring.tick(stiffness: SpringConstants.gapStiffness, damping: SpringConstants.gapDamping, dt: dt)
        }

        #expect(abs(spring.current - 200) < SpringConstants.positionThreshold)
    }

    // MARK: - All Spring Types Converge

    @Test func testGapSpringConverges() {
        var spring = SpringState(current: 0, target: 50)
        let dt: Float = 1.0 / 60.0
        for _ in 0..<120 {
            _ = spring.tick(stiffness: SpringConstants.gapStiffness, damping: SpringConstants.gapDamping, dt: dt)
        }
        #expect(abs(spring.current - spring.target) < SpringConstants.positionThreshold)
    }

    @Test func testLiftSpringConverges() {
        var spring = SpringState(current: 1.0, target: 1.15)
        let dt: Float = 1.0 / 60.0
        for _ in 0..<120 {
            _ = spring.tick(stiffness: SpringConstants.liftStiffness, damping: SpringConstants.liftDamping, dt: dt)
        }
        #expect(abs(spring.current - spring.target) < SpringConstants.scaleThreshold)
    }

    @Test func testSettleSpringConverges() {
        var spring = SpringState(current: 0, target: 300)
        let dt: Float = 1.0 / 60.0
        for _ in 0..<300 { // Settle is less damped, needs more time
            _ = spring.tick(stiffness: SpringConstants.settleStiffness, damping: SpringConstants.settleDamping, dt: dt)
        }
        #expect(abs(spring.current - spring.target) < SpringConstants.positionThreshold)
    }

    // MARK: - Spring Constants

    @Test func testSpringConstantsArePositive() {
        #expect(SpringConstants.gapStiffness > 0)
        #expect(SpringConstants.gapDamping > 0)
        #expect(SpringConstants.liftStiffness > 0)
        #expect(SpringConstants.liftDamping > 0)
        #expect(SpringConstants.settleStiffness > 0)
        #expect(SpringConstants.settleDamping > 0)
    }

    @Test func testThresholdsArePositive() {
        #expect(SpringConstants.velocityThreshold > 0)
        #expect(SpringConstants.positionThreshold > 0)
        #expect(SpringConstants.scaleThreshold > 0)
    }

    // MARK: - Snap with Various States

    @Test func testSnapFromMoving() {
        var spring = SpringState(current: 50, target: 200, velocity: -1000)
        spring.snap()
        #expect(spring.current == 200)
        #expect(spring.velocity == 0)
    }

    @Test func testSnapAlreadyAtTarget() {
        var spring = SpringState(current: 100, target: 100, velocity: 0)
        spring.snap()
        #expect(spring.current == 100)
        #expect(spring.velocity == 0)
    }
}
