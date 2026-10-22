# Orbit: liquid bubble onboarding

A SwiftUI onboarding for **Orbit**, a friend-circle app in the spirit of Bump and Snapchat, told in
liquid bubbles:

1. **It starts with you.** One bubble, its liquid outline slowly undulating.
2. **Bump to connect.** A friend drifts in and collides with you; you fuse into one wobbling blob,
   then pull apart still joined by a thread of liquid.
3. **Your circle grows.** Friends bud out of each of you. Their necks never snap; they stretch into
   threads, so your circle becomes one connected liquid network.
4. **Your world, in orbit.** Everything drains into one drop that swells into Earth, with friends
   clinging to its rim like droplets, slowly orbiting.

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
launch, and "Replay onboarding" on the last screen starts it again.

## How the liquid works

- **Goo** (`Bubbles/Liquid.metal`, used by `GooLayer` in `Bubbles/BubbleStage.swift`): a per-pixel
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
