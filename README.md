# Orbit: liquid bubble onboarding

A SwiftUI onboarding for **Orbit**, a friend-circle app, told in liquid bubbles. There are two
versions; the home screen at the end lets you replay either.

**v2** (the default) opens on Earth, and its glass orbs are the liquid themselves:

1. **Your world.** Earth alone, big, swelling in with a bounce.
2. **It starts with you.** Earth shrinks to a planet below, and you bud out of its surface like a
   droplet and pinch off.
3. **Your people find you.** Friends bud out of Earth one by one and melt onto your bubble.
4. **Your world, in orbit.** Friends glide into two orbits around you going opposite ways, melting
   into each other as they pass, and Earth, now small, orbits you too. After "Get started"
   everything melts back into Earth, so a recording loops.

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
launch, and "Replay v1" or "Replay v2" on the last screen plays that version.

## How the liquid works

- **v2 glass** (`Bubbles/GlassLiquid.swift`, the `glassLiquid` shader in `Bubbles/Liquid.metal`):
  each photo is drawn flat where its orb is, and the shader turns that layer into glass. The orbs
  are joined with a smooth union, so close ones melt into one shape with a neck and pinch apart
  again; the surface is an exact sphere for a lone orb; a fisheye lens bulges each photo; light
  sits on the rim, and a soft glow in each photo's own colour surrounds the glass.
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
  to initials.

## Checking changes without Xcode

`SWIFTC=/path/to/swiftc tools/engine/run.sh` tests the animation engine with any Swift toolchain
(Linux included) and records a run; `tools/preview/run.sh` renders that run into a preview video.

## Credits

- Earth: NASA Goddard Space Flight Center, "Blue Marble" (public domain).
- Photos: [Unsplash](https://unsplash.com/license), free to use under the Unsplash License.
