# Orbit: liquid bubble onboarding

A SwiftUI onboarding for **Orbit**, a friend-circle app, told in liquid bubbles. There are three
versions; the home screen at the end lets you replay any of them.

**v3** (the default) is one screen that starts in the real world:

1. It opens on Paris in 3D satellite view (Apple's map, through MapKit) and pulls back through the
   sky to the whole Earth in space: "Everyone you love, in one orbit."
2. The black of space falls away and the globe shrinks into a small glass orb on a white page.
3. Your friends pop out of it in one crisp body of flat, pale liquid: five first, in a pentagon,
   then more out of them, and drops at the tips that keep pinching off and melting back. Drag
   around Earth to spin everyone, the globe with them.
4. "Meet Orbit." comes in under it, with two buttons. "Continue" melts everyone back into Earth
   and dives back into the city, so a recording loops.

**v2** is one screen in the style of the Wabi app:

1. Earth waits as a big glass dome rising from the bottom edge, under "Everyone you love, in one
   orbit." Swipe up and it follows your finger.
2. Let go and Earth flies up into a small glass orb, stretching like a drop and bending the text it
   passes through. Your friends bubble out of its surface into a floating cluster of liquid glass.
3. "Meet Orbit." fades in under it, with two glass buttons. "Continue" melts everything back into
   Earth, so a recording loops.

**v1** is the first story, photos on a pale lilac liquid: it starts with you, you bump into a
friend, your circle grows, and everyone forms a ring.

![Onboarding steps](docs/onboarding-steps.jpg)

`tools/preview/run.sh` renders a motion preview video from the real animation engine's output (see
below). It uses Nunito as a stand-in for SF Pro Rounded, so expect small differences from the
simulator.

## Run it

Needs Xcode 16 or later. There are no dependencies.

```sh
./scripts/run.sh                  # builds and launches in the booted simulator, or the newest iPhone
./scripts/run.sh "iPhone 16 Pro"  # or pick one
```

Or open `Orbit.xcodeproj`, choose an iPhone simulator and press ⌘R. Onboarding plays on every
launch, and "Replay v1", "Replay v2" or "Replay v3" on the last screen plays that version. v3's map
needs a network connection the first time (MapKit downloads the imagery).

## How the liquid works

- **v3 flat liquid** (`Bubbles/FlatLiquid.swift`, the `flatLiquid` shader in `Bubbles/Liquid.metal`):
  every photo, drop and Earth's pool is a circle; their signed distances are joined with a smooth
  minimum, so neighbours share one crisp outline with wide, soft fillets, and a bud swells out of
  its parent's edge with a neck that thins and pinches off. No blur. The fill is flat, darkened a
  touch just inside the edge. Photos are sharp discs that pop in once their liquid has swollen.
- **v3 Earth** (`Bubbles/EarthZoom.swift`): a live MapKit map with realistic elevation, zoomed by a
  keyframe animation that is even in log space, so rooftops to orbit keep one sense of speed. Once
  it reaches space the app finds the globe on screen (from where two known points land), cuts the
  map to it and scales it into the orb, where real Liquid Glass (iOS 26) sits on top.
- **v2 glass** (`Bubbles/GlassLiquid.swift`, the `glassLiquid` shader in `Bubbles/Liquid.metal`):
  the photos and the headline are drawn flat into one layer, and the shader turns it into glass.
  The orbs are joined with a smooth union, so close ones melt into one shape with a neck of clear
  glass and pinch apart again; a lone orb is an exact sphere; a fisheye lens bulges each photo and
  bends text behind the glass; moving orbs stretch along their motion like drops; the rim is
  iridescent, and a soft glow in each photo's own colour surrounds the glass.
- **v1 goo** (`Bubbles/Liquid.metal`, used by `GooLayer` in `Bubbles/BubbleStage.swift`): a per-pixel
  Metal shader, applied with `.colorEffect` over the whole stage. Every photo is a disc and every
  thread a capsule, each with the soft shoulder a Gaussian blur would give it, summed into one
  field, which is cut at 0.5 over a short ramp. Where two come close the shoulders add up, so
  neighbours round into one outline and a budding bubble drags a neck of liquid behind it. No
  lighting: inside, the colour is a flat pale wash. Each bubble carries its own tint, and tints
  blend where their liquid meets.
- **Photos** (`Components/BubbleFaces.swift`): each photo is a glass orb, drawn by the `glassOrb`
  shader in `Bubbles/Liquid.metal`: the photo sits a little behind a glass sphere, gently
  magnified and bending round at the rim, with soft reflections on the rim and a bright crescent
  at the bottom. In a debug build, triple-tap the onboarding screen to switch to the plain look, a
  sharp photo under a feathered circular mask (`SoftPhoto`).
- **Motion** (`Bubbles/BubbleEngine.swift`): each bubble is a pure function of time driven by
  closed-form springs, so interrupting a transition never jumps. A hidden bubble rides inside
  its parent every frame, which is why new friends bud out of a moving parent rather than out of
  thin air.
- **Choreography** (`Bubbles/OrbitChoreography.swift`): the layouts and threads for each page, in a
  fixed 372 × 480 reference space that scales to the screen. Photos are packed tight, like the
  reference: a bud sits close enough to its parent that their liquid stays one shape. A page can
  be several keyframes: the bump collides, then separates; the last page drains into a drop,
  then swells into Earth.
- The stage is laid out between the heading and the footer but draws over the whole screen, so
  bubbles pushed aside slide off the real screen edge.

Reduce Motion swaps the springs for quick, non-bouncy ones and turns off the idle drift and the
spin. Each bud plays a soft haptic as it lets go of its parent.

## Make it yours

- **Copy**: `Onboarding/OnboardingStep.swift` (title, subtitle and scene per page).
- **Colors**: `Theme/Theme.swift` (the liquid's lilac, butter and sky washes; mirror them in `GooTint`).
- **Photos**: replace `friend-1` (you) … `friend-9` in `Assets.xcassets`. A missing photo falls back
  to initials. v3 also shows `place-1` … `place-5`.
- **v3's city**: `EarthZoom.city` and `EarthZoom.street` (other good Flyover cities are listed there).

## Checking changes without Xcode

`SWIFTC=/path/to/swiftc tools/engine/run.sh` tests the animation engine with any Swift toolchain
(Linux included) and records a run; `tools/preview/run.sh` renders that run into a preview video
(`VERSION=v2` or `VERSION=v3` for the others). v3's preview can't draw the map: it stands in for
the zoom with the Earth photo, labelled.

## Credits

- Earth: NASA Goddard Space Flight Center, "Blue Marble" (public domain). v3's map: Apple Maps, via MapKit.
- Photos: [Unsplash](https://unsplash.com/license), free to use under the Unsplash License.
