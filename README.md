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
  overlap they fuse, which is the liquid neck you see when bubbles meet or bud. Each filter sits on
  its own nested layer: with both on one context, SwiftUI applies them in an order that makes the
  circles glow instead of fusing. Three small satellites circle inside each blob so its outline
  keeps moving, threads are chains of dots that fuse into a strand (thinnest in the middle, so
  that's where they snap), and the liquid is lit like a gel: lighter top left, deeper bottom right.
- **Photos** (`Components/BubbleFaces.swift`, `SoftPhoto`): rendered once each with Core Image: a
  sharp middle dissolving into a blurred rim washed with the liquid's color. No borders or shadows.
- **Motion** (`Bubbles/BubbleEngine.swift`): each bubble is a pure function of time driven by
  closed-form, near-critically-damped springs, so transitions flow without bouncing and
  interrupting one never jumps. A hidden bubble rides inside its parent every frame, which is why
  new friends bud out of a moving parent rather than out of thin air.
- **Choreography** (`Bubbles/OrbitChoreography.swift`): the layouts and threads for each page, in a
  fixed 372 × 480 reference space that scales to the screen. A page can be several keyframes: the
  bump collides, then separates; the last page drains into a drop, then swells into Earth.
- The stage is laid out between the heading and the footer but draws over the whole screen, so
  bubbles pushed aside slide off the real screen edge.

Reduce Motion swaps the springs for quick, non-bouncy ones and turns off the idle drift and the
spin. Each bud plays a soft haptic as it lets go of its parent.

## Make it yours

- **Copy**: `Onboarding/OnboardingStep.swift` (title, subtitle and scene per page).
- **Colors**: `Theme/Theme.swift` (the liquid's light, base, deep and shade colors).
- **Photos**: replace `friend-1` (you) … `friend-8` in `Assets.xcassets`. A missing photo falls back
  to initials.

## Credits

- Earth: NASA Goddard Space Flight Center, "Blue Marble" (public domain).
- Photos: [Unsplash](https://unsplash.com/license), free to use under the Unsplash License.
