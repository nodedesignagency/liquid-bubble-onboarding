import Foundation

/// Closed-form damped spring from 0 to 1, starting at rest.
///
/// The bubble engine evaluates every bubble as a pure function of time, so it needs
/// the spring as math rather than as a SwiftUI `Animation`. `response` and
/// `dampingRatio` mean the same thing as in `Animation.spring(response:dampingFraction:)`.
struct SpringCurve {
    var response: Double
    var dampingRatio: Double

    // v1 is close to critically damped: the liquid flows rather than bounces. v2 adds bouncier
    // arrivals (`budBouncy`, `inflateBouncy`), used by targets marked `jelly` that are appearing.

    /// Carries a new bubble out of its parent slowly enough for the neck to stretch before it snaps.
    static let bud = SpringCurve(response: 0.95, dampingRatio: 0.82)
    /// Inflates a new bubble, with the faintest settle at the end.
    static let inflate = SpringCurve(response: 0.8, dampingRatio: 0.78)
    /// Rearranges bubbles that are already on screen.
    static let glide = SpringCurve(response: 0.9, dampingRatio: 0.88)
    /// Two bubbles colliding: they squash together and settle with a soft wobble.
    static let jelly = SpringCurve(response: 0.8, dampingRatio: 0.62)
    /// v2: a bubble budding out with the reference's bounce, overshooting a little and settling.
    static let budBouncy = SpringCurve(response: 1.0, dampingRatio: 0.66)
    /// v2: swelling with a bounce, like the reference's bloom.
    static let inflateBouncy = SpringCurve(response: 0.75, dampingRatio: 0.58)
    /// A big change of size on a `jelly` bubble (v2's Earth shrinking from the dome to its orb and
    /// back): a 10% bounce on a radius that changes by 190pt dipped Earth almost to nothing before
    /// it popped back. This settles with a hint of give instead.
    static let swell = SpringCurve(response: 0.7, dampingRatio: 0.82)
    /// v2: Earth settling back after the finger lets go, with a little give.
    static let liftSettle = SpringCurve(response: 0.6, dampingRatio: 0.72)
    /// Pulls a bubble back into its parent.
    static let absorb = SpringCurve(response: 0.75, dampingRatio: 1)
    /// Deflates a bubble that is being absorbed. Slower than `absorb`, so it melts in instead of vanishing.
    static let deflate = SpringCurve(response: 0.85, dampingRatio: 1)
    /// Used for everything when Reduce Motion is on: quick, no overshoot.
    static let calm = SpringCurve(response: 0.4, dampingRatio: 1)

    func progress(at time: Double) -> Double {
        guard time > 0 else { return 0 }
        let omega = 2 * Double.pi / response
        if dampingRatio < 1 {
            let dampedOmega = omega * (1 - dampingRatio * dampingRatio).squareRoot()
            let envelope = exp(-dampingRatio * omega * time)
            return 1 - envelope * (cos(dampedOmega * time) + dampingRatio * omega / dampedOmega * sin(dampedOmega * time))
        } else {
            return 1 - exp(-omega * time) * (1 + omega * time)
        }
    }
}
