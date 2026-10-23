# Orbit: liquid bubble onboarding

A SwiftUI onboarding for **Orbit**, a friend-circle app, told in liquid bubbles. There are three
versions; the home screen at the end lets you replay any of them.

**v3** (the default) is one dark screen that starts in the real world:

1. It opens on Paris in 3D (Apple's map, through MapKit), once it has fully loaded, with a big
   dome of clear glass rising from the bottom edge, "Swipe up to enter" on the glass.
2. Swipe it away and the city pulls back through the sky. The zoom is drawn from satellite
   snapshots fetched while the city loaded, so it never waits on the network: the photo turns in
   place into a glowing map, which curls into a holographic globe as it pulls back: "Everyone you
   love, in one orbit."
3. Six friends pop up as pins on their cities, then lift off into orbit round Earth, each joined
   to it by a neck of liquid glass (real Liquid Glass on iOS 26), over a faint dot grid.
4. "Meet Orbit." comes in under it, with two buttons. Drag around Earth to spin everyone, the globe
   with them. Tap a friend and everyone else melts into Earth, which parks in the top-left corner,
   while the friend takes the middle, globe-size, and four moments from their week (places,
   coffee, food) bud out of them; tap Earth to come back. "Continue" melts everyone back into
   Earth and dives back into the city, and the dome rises again, so a recording loops.

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
launch, and "Replay v1", "Replay v2" or "Replay v3" on the last screen plays that version. v3's city
and zoom need a network connection (MapKit downloads the imagery); it waits for them before moving.

## How the liquid works

- **v3 globe** (`Bubbles/HoloGlobe.swift`, the `holoGlobe` shader in `Bubbles/Liquid.metal`): a
  sphere drawn per pixel from a signed distance field of the world's coastlines (`land-sdf`, from
  Natural Earth, built by `tools/globe/landsdf.py`), so it is sharp at any size: continents
  glowing from aqua to lime with a little relief, a dark teal sea, a mint rim and a green aura
  (Aurora). Four more colourways in the hues of the FlightElite onboarding (`GlobePalette`: Dusk,
  Afterglow, Midnight bloom, Lavender sky); in a debug build, long-press the screen to try the next.
  During the zoom it is drawn flat at first, in the same projection and scale as the satellite
  snapshots, so the photo turns into it coast on coast, then curls into the sphere.
- **v3 zoom** (`Bubbles/EarthZoom.swift`): the live map only for the city; the zoom out runs through
  satellite snapshots at widening spans (fetched while the city loads), crossfaded by scale and
  eased in log space, so nothing loads mid-zoom. The first snapshots are drawn in 3D like the live
  map, so the handover is seamless.
- **v3 glass** (`Bubbles/GlassNetwork.swift`): Earth and each friend (or moment) sit in a ring of
  Liquid Glass, joined to whoever is in the middle by metaball necks, all unioned into one outline
  and drawn as one shape of glass, so there are no seams. The page under the glass is filled
  plain, so the dot grid doesn't show through it.
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
  to initials. v3 uses six: your friends (`OrbitChoreography.homeCircle`), pinned on the cities
  in `OrbitChoreography.people`. Their moments are `moment-<friend>-<n>` (four each).
- **v3's city**: `EarthZoom.city` and its cameras (other good Flyover cities are listed there).

## Checking changes without Xcode

`SWIFTC=/path/to/swiftc tools/engine/run.sh` tests the animation engine with any Swift toolchain
(Linux included) and records a run; `tools/preview/run.sh` renders that run into a preview video
(`VERSION=v2` or `VERSION=v3` for the others). v3's preview can't draw the city or the snapshots:
those parts are labelled stand-ins.

## Credits

- Earth (v1, v2): NASA Goddard Space Flight Center, "Blue Marble" (public domain). v3's city and
  zoom imagery: Apple Maps, via MapKit. v3's coastlines: Natural Earth (public domain).
- Photos: [Unsplash](https://unsplash.com/license), free to use under the Unsplash License. v3's
  moments: Freepik stock (via Magnific), credits and licences in `docs/moment-photos.json`.
