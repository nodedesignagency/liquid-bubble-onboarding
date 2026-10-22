import Foundation

func fmt(_ p: CGPoint) -> String { String(format: "(%.1f, %.1f)", Double(p.x), Double(p.y)) }
let scenes: [OrbitScene] = [.you, .bump, .circle, .world, .collapse, .planet, .rise, .gather, .orbit]
var failures = 0
func check(_ ok: Bool, _ msg: String) { if !ok { failures += 1; print("FAIL:", msg) } }

/// Plays scenes like BubbleStage does: a new scene cancels the old one's pending keyframes,
/// and each keyframe is applied when its time comes.
final class Player {
    let engine = BubbleEngine(bubbleCount: OrbitChoreography.bubbleCount)
    private var pending: [(Double, BubbleLayout)] = []
    func play(_ scene: OrbitScene, at t0: Double) {
        pending = OrbitChoreography.keyframes(for: scene).map { (t0 + $0.after, $0.layout) }
        tick(t0)
    }
    func tick(_ now: Double) {
        while let first = pending.first, first.0 <= now {
            _ = engine.transition(to: first.1, at: first.0)
            pending.removeFirst()
        }
    }
    func frame(_ now: Double) -> [RenderedBubble] { tick(now); return engine.snapshot(at: now) }
}

// 1. Each scene settles on its final targets (through the camera) and fits the stage.
for scene in scenes {
    let player = Player()
    player.play(scene, at: 0)
    _ = player.frame(2)
    let final = OrbitChoreography.keyframes(for: scene).last!.layout
    player.engine.reduceMotion = true
    let settled = player.frame(9)
    for (id, t) in final.targets.enumerated() {
        let b = settled[id]
        check(abs(b.radius - t.radius) < 0.05, "\(scene) bubble \(id) radius \(b.radius) vs \(t.radius)")
        if t.radius >= 1 && final.spin == 0 && t.orbitRate == 0 {
            check(hypot(b.center.x - t.center.x, b.center.y - t.center.y) < 0.1, "\(scene) bubble \(id) at \(fmt(b.center)) vs \(fmt(t.center))")
        }
    }
    let visible = settled.filter { $0.radius >= 1 }
    // Sideways, bubbles may run off the screen edge (the stage draws full width). Vertically they
    // must stay between the heading and the footer.
    // A bubble whose centre is itself past the stage's edge (Earth as v2's horizon) is meant to run off it.
    // v1's liquid reaches about 24% past a photo; v2 has only a 5pt glow around the glass.
    let isV2 = [OrbitScene.planet, .rise, .gather, .orbit].contains(scene)
    let reach = { (b: RenderedBubble) in isV2 ? b.radius + 5 : b.radius * 1.24 }
    let tooTall = visible.filter { abs($0.center.y) + reach($0) > 242 && abs($0.center.x) - $0.radius < 201 && abs($0.center.y) <= 240 }
    let offSide = visible.filter { abs($0.center.x) + reach($0) > 201 && abs($0.center.x) - $0.radius < 201 }
    print("\(scene): \(visible.count) visible, radii \(Set(visible.map { Int($0.radius.rounded()) }).sorted()), partly off the side: \(offSide.map(\.id))")
    check(tooTall.isEmpty, "\(scene) bubbles \(tooTall.map(\.id)) run into the heading or footer")
}

// 1b. At rest, which bubbles fuse? Only crews and the ring should.
for scene in [OrbitScene.you, .bump, .circle, .world] {
    let player = Player(); player.play(scene, at: 0); _ = player.frame(2); player.engine.reduceMotion = true
    let s = player.frame(9).filter { $0.radius >= 1 }
    let pad = OrbitChoreography.haloWidth
    var fused: [String] = []
    for i in s.indices { for j in s.indices where j > i {
        let gap = hypot(s[i].center.x - s[j].center.x, s[i].center.y - s[j].center.y) - s[i].radius - pad(s[i].radius) - s[j].radius - pad(s[j].radius)
        if gap < 10 { fused.append("\(s[i].id)-\(s[j].id)(\(Int(gap)))") }
    }}
    print("  \(scene) fused pairs: \(fused.joined(separator: " "))")
}

// 1c. v1 at rest: no two photos overlap (so stacking order can never show), and the ring's gaps are even.
for scene in [OrbitScene.you, .circle, .world] {
    let player = Player(); player.play(scene, at: 0); _ = player.frame(2); player.engine.reduceMotion = true
    let s = player.frame(9).filter { $0.radius >= 1 }
    var gaps: [CGFloat] = []
    for i in s.indices { for j in s.indices where j > i {
        gaps.append(hypot(s[i].center.x - s[j].center.x, s[i].center.y - s[j].center.y) - s[i].radius - s[j].radius)
    }}
    if let smallest = gaps.min() {
        print("  \(scene) smallest gap between photos: \(String(format: "%.1f", Double(smallest))) (reference points)")
        check(smallest > 1.4, "\(scene) photos overlap or touch at rest")
    }
}

// 1d. v2: which orbs melt together (gap under 0.7 x blend = 8.4 reference points)?
for scene in [OrbitScene.planet, .rise, .gather] {
    let player = Player(); player.play(scene, at: 0); _ = player.frame(3); player.engine.reduceMotion = true
    let s = player.frame(9).filter { $0.radius >= 1 }
    var melted: [String] = []
    for i in s.indices { for j in s.indices where j > i {
        let gap = hypot(s[i].center.x - s[j].center.x, s[i].center.y - s[j].center.y) - s[i].radius - s[j].radius
        if gap < 8.4 { melted.append("\(s[i].id)-\(s[j].id)") }
    }}
    print("  \(scene) melted together: \(melted.joined(separator: " "))")
}
// In orbit, the inner and outer rings should melt into each other when they pass, and nothing
// should melt into you in the middle.
do {
    let player = Player(); player.play(.orbit, at: 0)
    var passes = Set<String>(), touchesYou = false
    for step in 0..<1200 {
        let s = player.frame(3 + Double(step) / 20)
        for i in 2...7 { for j in [0, 5, 6, 7] where j != i && (i <= 4) {
            let gap = hypot(s[i].center.x - s[j].center.x, s[i].center.y - s[j].center.y) - s[i].radius - s[j].radius
            if gap < 8.4 { passes.insert("\(i)-\(j)") }
        }}
        for i in [0, 2, 3, 4, 5, 6, 7] {
            let gap = hypot(s[i].center.x - s[1].center.x, s[i].center.y - s[1].center.y) - s[i].radius - s[1].radius
            if gap < 8.4 { touchesYou = true }
        }
    }
    print("  orbit: inner and outer orbs that melt together while passing, over a minute: \(passes.sorted().joined(separator: " "))")
    check(passes.count >= 6, "orbit: the rings hardly ever meet")
    check(!touchesYou, "orbit: an orbiting bubble melts into you")
}

// 2. Every ordered pair of scenes, interrupted mid-flight: no NaN, nothing teleports.
// The two versions never mix in the app (each has its own onboarding screen), so each version's
// scenes are interrupted only by its own.
let families: [[OrbitScene]] = [[.you, .bump, .circle, .world, .collapse], [.planet, .rise, .gather, .orbit]]
var maxJump: CGFloat = 0
for family in families { for a in family { for b in family { for c in family where c != b {
    let player = Player()
    var t = 0.0
    player.play(a, at: t)
    for _ in 0..<5 { t += 0.6; _ = player.frame(t) }
    player.play(b, at: t); t += 0.37
    var last = player.frame(t)
    player.play(c, at: t)
    for step in 1...400 {
        let now = t + Double(step) / 120
        let frame = player.frame(now)
        for (i, bub) in frame.enumerated() {
            check(bub.center.x.isFinite && bub.center.y.isFinite && bub.radius.isFinite, "NaN \(a)->\(b)->\(c) id \(i)")
            if bub.radius > 1 && last[i].radius > 1 {
                maxJump = max(maxJump, hypot(bub.center.x - last[i].center.x, bub.center.y - last[i].center.y))
            }
        }
        last = frame
    }
}}}}
print("largest per-frame move of a visible bubble at 120 Hz: \(String(format: "%.1f", Double(maxJump))) pt")
check(maxJump < 12, "something moves too fast to read as smooth")

// 3. Budding on page 3: when does your first friend's neck let go of you, versus when its thread is strong
//    enough to show (about 0.8)? The thread should be there by the time the neck would break.
let p3 = Player()
p3.play(.you, at: 0); _ = p3.frame(3)
p3.play(.circle, at: 3)
var released: Double?, threadReady: Double?
for step in 0...300 {
    let t = 3 + Double(step) / 100
    let s = p3.frame(t)
    let pad = OrbitChoreography.haloWidth
    let a = s[1], b = s[3]
    if b.radius > 1, released == nil {
        let gap = hypot(a.center.x - b.center.x, a.center.y - b.center.y) - (a.radius + pad(a.radius)) - (b.radius + pad(b.radius))
        if gap > 7 { released = t - 3 }
    }
    if threadReady == nil, let th = p3.engine.threads(at: t).first(where: { $0.a == 1 && $0.b == 3 }), th.strength > 0.8 { threadReady = t - 3 }
}
if let released {
    print(String(format: "bud 3: neck would let go at %.2f s, thread reaches 0.8 at %.2f s", released, threadReady ?? -1))
    check((threadReady ?? 99) <= released + 0.1, "thread forms too late, the neck snaps first")
} else {
    print("bud 3 stays fused to you (packed like the reference), so its thread timing doesn't matter")
}
print(failures == 0 ? "ALL CHECKS PASSED" : "\(failures) FAILURES")
if failures > 0 { exit(1) }
