import Foundation
// Records a scripted run through onboarding (bubbles and threads) for the preview renderer.
// Usage: record <frames.csv> <threads.csv> [v1|v2|v3]
// Keep the timings in sync with `tools/preview/render.py` (STEPS_V1), `render_v2.py` (V2_*) and
// `render_v3.py` (V3_*, which mirror `WorldOnboardingView`).
let version = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "v1"
let script: [(Double, OrbitScene)]
switch version {
// v2: the finger lifts Earth from 0.9 s and lets go at 2.2 s (the lift itself is replayed by
// render.py); "Continue" at 10 s.
case "v2": script = [(0, .gate), (2.2, .reveal), (10.0, .gate)]
// v3, with the city rendered and the imagery in at once: the city holds until 1.5 s, rises, zooms
// out to the globe until 6.45 s (render_v3.py replays the zoom), pins at 6.6 s, lift-off at 8 s;
// "Continue" at 14 s, back in the city by 18 s.
case "v3": script = [(0, .space), (6.6, .pins), (8.0, .bloom), (14.0, .space)]
default: script = [(0, .you), (3.0, .bump), (6.8, .circle), (10.6, .world), (15.0, .collapse)]
}
let end = version == "v1" ? 16.6 : version == "v2" ? 12.6 : 19.6, fps = 30.0
let engine = BubbleEngine(bubbleCount: OrbitChoreography.bubbleCount)
var pending: [(Double, BubbleLayout)] = []
var next = 0
var out = "frame,id,x,y,r,tr,tg,tb,depth,leaving,vx,vy,full,appearing\n"
var threadsOut = "frame,a,b,strength\n"
for f in 0..<Int(end * fps) {
    let t = Double(f) / fps
    while next < script.count && script[next].0 <= t {
        pending = OrbitChoreography.keyframes(for: script[next].1).map { (script[next].0 + $0.after, $0.layout) }
        next += 1
    }
    while let first = pending.first, first.0 <= t {
        // v2 and v3 open on their first scene already settled (BubbleStage's `startsSettled`).
        let settled = version != "v1" && first.0 == 0
        _ = engine.transition(to: first.1, at: settled ? -60 : first.0)
        pending.removeFirst()
    }
    // Velocity (reference points per second) the way BubbleStage measures it: from 1/120 s earlier.
    let earlier = engine.snapshot(at: t - 1.0 / 120)
    for b in engine.snapshot(at: t) {
        let vx = (b.center.x - earlier[b.id].center.x) * 120, vy = (b.center.y - earlier[b.id].center.y) * 120
        out += "\(f),\(b.id),\(b.center.x),\(b.center.y),\(b.radius),\(b.tint.red),\(b.tint.green),\(b.tint.blue),\(b.depth),\(b.isLeaving ? 1 : 0),\(vx),\(vy),\(b.fullRadius),\(b.isAppearing ? 1 : 0)\n"
    }
    for th in engine.threads(at: t) { threadsOut += "\(f),\(th.a),\(th.b),\(th.strength)\n" }
}
try! out.write(toFile: CommandLine.arguments[1], atomically: true, encoding: .utf8)
try! threadsOut.write(toFile: CommandLine.arguments[2], atomically: true, encoding: .utf8)
