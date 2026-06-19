import Testing
import Foundation
@testable import LiquidBar

@Suite
struct SpringPhysicsTests {
    @Test func testSpringConvergence() {
        // Gap spring (280/20) should reach target within threshold after enough ticks
        var spring = SpringState(current: 0, target: 100)
        let dt: Float = 1.0 / 60.0

        // Simulate 2 seconds (120 frames at 60fps)
        for _ in 0..<120 {
            _ = spring.tick(stiffness: SpringConstants.gapStiffness, damping: SpringConstants.gapDamping, dt: dt)
        }

        #expect(abs(spring.current - spring.target) < SpringConstants.positionThreshold)
        #expect(abs(spring.velocity) < SpringConstants.velocityThreshold)
    }

    @Test func testSpringOvershoot() {
        // Settle spring (200/12) is underdamped — should overshoot target
        var spring = SpringState(current: 0, target: 100)
        let dt: Float = 1.0 / 60.0

        var maxValue: Float = 0
        // Simulate 1 second
        for _ in 0..<60 {
            _ = spring.tick(stiffness: SpringConstants.settleStiffness, damping: SpringConstants.settleDamping, dt: dt)
            maxValue = max(maxValue, spring.current)
        }

        // Underdamped spring should overshoot past 100
        #expect(maxValue > spring.target)
    }

    @Test func testSpringSnap() {
        var spring = SpringState(current: 50, target: 200, velocity: 1000)
        spring.snap()

        #expect(spring.current == spring.target)
        #expect(spring.velocity == 0)
    }

    @Test func testSpringHighFrequency() {
        // Large dt should not cause explosion thanks to dt capping in the caller
        var spring = SpringState(current: 0, target: 100)

        // Even with a very large dt, the spring should not explode
        // The caller caps dt to 1/30, but let's test with 1/30 directly
        let dt: Float = 1.0 / 30.0
        for _ in 0..<60 {
            _ = spring.tick(stiffness: SpringConstants.gapStiffness, damping: SpringConstants.gapDamping, dt: dt)
        }

        // Should still converge, not explode to infinity
        #expect(spring.current.isFinite)
        #expect(spring.velocity.isFinite)
        #expect(abs(spring.current - spring.target) < SpringConstants.positionThreshold)
    }

    @Test func testSpringTickReturnValue() {
        // tick() returns true while animating, false when converged
        var spring = SpringState(current: 0, target: 100)
        let dt: Float = 1.0 / 60.0

        // First tick should report still animating
        let animating = spring.tick(stiffness: SpringConstants.gapStiffness, damping: SpringConstants.gapDamping, dt: dt)
        #expect(animating == true)

        // After many ticks, should report converged
        for _ in 0..<300 {
            _ = spring.tick(stiffness: SpringConstants.gapStiffness, damping: SpringConstants.gapDamping, dt: dt)
        }
        let done = spring.tick(stiffness: SpringConstants.gapStiffness, damping: SpringConstants.gapDamping, dt: dt)
        #expect(done == false)
    }

    @Test func testSpringAtRest() {
        // Spring already at target should not animate
        var spring = SpringState(current: 50, target: 50, velocity: 0)
        let animating = spring.tick(stiffness: SpringConstants.gapStiffness, damping: SpringConstants.gapDamping, dt: 1.0 / 60.0)
        #expect(animating == false)
        #expect(spring.current == 50)
    }
}
