import Foundation
// Records a scripted run through onboarding (bubbles and threads) for the preview renderer.
let script: [(Double, OrbitScene)] = [(0, .you), (3.0, .bump), (6.8, .circle), (10.6, .world), (15.0, .collapse)]
let end = 16.6, fps = 30.0
let engine = BubbleEngine(bubbleCount: OrbitChoreography.bubbleCount)
var pending: [(Double, BubbleLayout)] = []
var next = 0
var out = "frame,id,x,y,r,tr,tg,tb\n"
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
    for b in engine.snapshot(at: t) {
        out += "\(f),\(b.id),\(b.center.x),\(b.center.y),\(b.radius),\(b.tint.red),\(b.tint.green),\(b.tint.blue)\n"
    }
    for th in engine.threads(at: t) { threadsOut += "\(f),\(th.a),\(th.b),\(th.strength)\n" }
}
try! out.write(toFile: CommandLine.arguments[1], atomically: true, encoding: .utf8)
try! threadsOut.write(toFile: CommandLine.arguments[2], atomically: true, encoding: .utf8)
