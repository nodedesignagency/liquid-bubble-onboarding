import Foundation

/// Closed-form damped spring from 0 to 1, starting at rest.
///
/// The bubble engine evaluates every bubble as a pure function of time, so it needs
/// the spring as math rather than as a SwiftUI `Animation`. `response` and
/// `dampingRatio` mean the same thing as in `Animation.spring(response:dampingFraction:)`.
struct SpringCurve {
    var response: Double
    var dampingRatio: Double

    /// Shoots a new bubble out of its parent with a little overshoot.
    static let pop = SpringCurve(response: 0.62, dampingRatio: 0.56)
    /// Inflates a new bubble; bouncier than `pop` so it visibly "plops" into shape.
    static let inflate = SpringCurve(response: 0.5, dampingRatio: 0.5)
    /// Rearranges bubbles that are already on screen.
    static let glide = SpringCurve(response: 0.75, dampingRatio: 0.74)
    /// Pulls a bubble back into its parent.
    static let absorb = SpringCurve(response: 0.42, dampingRatio: 0.9)
    /// Deflates a bubble that is being absorbed. Slower than `absorb` so it melts in instead of vanishing.
    static let deflate = SpringCurve(response: 0.6, dampingRatio: 1)
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
