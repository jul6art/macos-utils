import Foundation

/// A value that follows its target like a muscle: quick to move, softer to let go, never overshooting
/// (spec, § 7.1, point 3). Exponential approach, with its own time constants for rising and falling.
struct Follower: Sendable {
    var value: Float = 0
    let rise: Float
    let fall: Float

    init(rise: Float, fall: Float, value: Float = 0) {
        self.rise = rise
        self.fall = fall
        self.value = value
    }

    mutating func update(towards target: Float, dt: Float) {
        let tau = target > value ? rise : fall
        let alpha = tau <= 0 ? 1 : 1 - exp(-dt / tau)
        value += (target - value) * alpha
    }
}

/// A damped spring, for the head: it can sway a little past its target, as a head does.
struct HeadSpring: Sendable {
    var value: Float = 0
    var velocity: Float = 0
    let stiffness: Float
    let damping: Float

    init(frequency: Float, dampingRatio: Float) {
        let omega = 2 * Float.pi * frequency
        stiffness = omega * omega
        damping = 2 * dampingRatio * omega
    }

    mutating func update(towards target: Float, dt: Float) {
        // Small fixed steps keep it stable whatever the frame rate.
        var remaining = dt
        while remaining > 0 {
            let step = min(remaining, 1 / 240)
            let acceleration = stiffness * (target - value) - damping * velocity
            velocity += acceleration * step
            value += velocity * step
            remaining -= step
        }
    }
}
