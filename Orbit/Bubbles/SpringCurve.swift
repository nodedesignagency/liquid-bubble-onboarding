import Foundation

/// Closed-form damped spring from 0 to 1, starting at rest.
///
/// The bubble engine evaluates every bubble as a pure function of time, so it needs
/// the spring as math rather than as a SwiftUI `Animation`. `response` and
/// `dampingRatio` mean the same thing as in `Animation.spring(response:dampingFraction:)`.
struct SpringCurve {
    var response: Double
    var dampingRatio: Double

    // Everything is close to critically damped: the liquid should flow, not bounce.

    /// Carries a new bubble out of its parent slowly enough for the neck to stretch before it snaps.
    static let bud = SpringCurve(response: 0.95, dampingRatio: 0.82)
    /// Inflates a new bubble, with the faintest settle at the end.
    static let inflate = SpringCurve(response: 0.8, dampingRatio: 0.78)
    /// Rearranges bubbles that are already on screen.
    static let glide = SpringCurve(response: 0.9, dampingRatio: 0.88)
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
