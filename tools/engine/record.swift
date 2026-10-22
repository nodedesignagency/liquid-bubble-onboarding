import Foundation
// Records a scripted run through onboarding (bubbles and threads) for the preview renderer.
// Usage: record <frames.csv> <threads.csv> [v1|v2]
// Keep the timings in sync with `tools/preview/render.py` (STEPS_V1, and V2_* for v2).
let version = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "v1"
let script: [(Double, OrbitScene)] = version == "v2"
    // v2: the finger lifts Earth from 0.9 s and lets go at 2.2 s (the lift itself is replayed by
    // render.py); "Continue" at 10 s.
    ? [(0, .gate), (2.2, .reveal), (10.0, .gate)]
    : [(0, .you), (3.0, .bump), (6.8, .circle), (10.6, .world), (15.0, .collapse)]
let end = version == "v2" ? 12.6 : 16.6, fps = 30.0
let engine = BubbleEngine(bubbleCount: OrbitChoreography.bubbleCount)
var pending: [(Double, BubbleLayout)] = []
var next = 0
var out = "frame,id,x,y,r,tr,tg,tb,depth,leaving,vx,vy\n"
var threadsOut = "frame,a,b,strength\n"
for f in 0..<Int(end * fps) {
    let t = Double(f) / fps
    while next < script.count && script[next].0 <= t {
        pending = OrbitChoreography.keyframes(for: script[next].1).map { (script[next].0 + $0.after, $0.layout) }
        next += 1
    }
    while let first = pending.first, first.0 <= t {
        _ = engine.transition(to: first.1, at: first.0)
        pending.removeFirst()
    }
    // Velocity (reference points per second) the way BubbleStage measures it: from 1/120 s earlier.
    let earlier = engine.snapshot(at: t - 1.0 / 120)
    for b in engine.snapshot(at: t) {
        let vx = (b.center.x - earlier[b.id].center.x) * 120, vy = (b.center.y - earlier[b.id].center.y) * 120
        out += "\(f),\(b.id),\(b.center.x),\(b.center.y),\(b.radius),\(b.tint.red),\(b.tint.green),\(b.tint.blue),\(b.depth),\(b.isLeaving ? 1 : 0),\(vx),\(vy)\n"
    }
    for th in engine.threads(at: t) { threadsOut += "\(f),\(th.a),\(th.b),\(th.strength)\n" }
}
try! out.write(toFile: CommandLine.arguments[1], atomically: true, encoding: .utf8)
try! threadsOut.write(toFile: CommandLine.arguments[2], atomically: true, encoding: .utf8)
