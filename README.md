# Orbit: liquid bubble onboarding

A SwiftUI onboarding for **Orbit**, a friend-circle app in the spirit of Bump and Snapchat.
Earth sits in the middle and friends bud out of it like liquid. Then Maya's friends bud out of her,
everyone regroups into crews, and the crews melt into one drop that bursts into a slowly orbiting ring.

![Onboarding steps](docs/onboarding-steps.jpg)

[`docs/onboarding-preview.mp4`](docs/onboarding-preview.mp4) is a motion preview rendered from the
real animation engine's output. It uses Nunito as a stand-in for SF Pro Rounded and approximates
SwiftUI's blur, so expect small differences from the simulator.

## Run it

Needs Xcode 16 or later. There are no dependencies.

```sh
./scripts/run.sh                  # builds and launches in the booted simulator, or the newest iPhone
./scripts/run.sh "iPhone 16 Pro"  # or pick one
```

Or open `Orbit.xcodeproj`, choose an iPhone simulator and press ⌘R. Onboarding plays on every
launch, and "Replay onboarding" on the last screen starts it again.

## How the liquid works

- **Goo** (`Bubbles/BubbleStage.swift`, `GooLayer`): every bubble draws a slightly larger circle
  into a `Canvas` layer that is blurred, then cut back with `alphaThreshold`. Where two blurs
  overlap they fuse, which is the liquid neck you see when a bubble buds out. Each filter sits on
  its own nested layer: with both on one context, SwiftUI applies them in an order that makes the
  circles glow instead of fusing. The blob is filled with soft lavender, crews glow in their own
  tint, and the edge is feathered.
- **Motion** (`Bubbles/BubbleEngine.swift`): each bubble is a pure function of time driven by
  closed-form, near-critically-damped springs, so transitions flow without bouncing and
  interrupting one never jumps. A hidden bubble rides inside its parent every frame, which is why
  new friends bud out of a moving parent rather than out of thin air.
- **Choreography** (`Bubbles/OrbitChoreography.swift`): the layouts for each page, in a fixed
  372 × 480 reference space that scales to the screen. A page can be several keyframes: the last
  page melts the crews into one drop, then bursts it into the ring.
- The stage is laid out between the heading and the footer but draws over the whole screen, so
  bubbles pushed aside slide off the real screen edge.

Reduce Motion swaps the springs for quick, non-bouncy ones and turns off the idle drift and the
spin. Each bud plays a soft haptic as it lets go of its parent.

## Make it yours

- **Copy**: `Onboarding/OnboardingStep.swift` (heading, sentence and scene per page).
- **Colors**: `Theme/Theme.swift` and the `GooTint` palette in `Bubbles/BubbleEngine.swift`.
- **Photos**: replace `friend-1` … `friend-10` in `Assets.xcassets`. A missing photo falls back to
  initials.

## Credits

- Earth: NASA Goddard Space Flight Center, "Blue Marble" (public domain).
- Photos: [Unsplash](https://unsplash.com/license), free to use under the Unsplash License.
