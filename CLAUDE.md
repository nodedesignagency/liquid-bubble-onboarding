# Orbit: liquid bubble onboarding

SwiftUI onboarding (iOS 17+, no dependencies) for Orbit, a friend-circle app in the spirit of
Bump and Snapchat, told with liquid "metaball" bubbles. See README.md for the overview.

## Working with the user

- Keep working on branch `claude/nice-cori-ypokiu`: commit and push every change there.
- **End every reply that changes code with this exact command**, so the user can pull and run:

  ```sh
  cd ~/liquid-bubble-onboarding && git pull && ./scripts/run.sh
  ```

- The user runs the app in the Simulator on their Mac (Xcode 27, iOS 27.1 SDK) and sends screen
  recordings and screenshots back. Pull frames out with ffmpeg and compare closely before answering.
- `scripts/run.sh` prints only the error lines when the build fails; the full log is in
  `build/xcodebuild.log` on their machine.
- Cloud sessions have no Xcode, so SwiftUI can't be compiled here. Be careful: run `swiftc -parse`
  on every file, run the engine checks (below), and after renaming anything grep the whole project
  for the old name (a renamed scene broke the build once).
- The user cares a lot about visual quality and calls out anything that looks generic ("AI slop").
  Think it through as a designer, check the rendered preview critically, and only then show it.

## Two versions

The app holds two onboardings. The home screen's "Replay v1" and "Replay v2" pick which one plays
(remembered across launches; v2 is the default). Work on v2 unless the user says otherwise, and
leave v1 as it is: it is the saved previous direction (commit 86737e4; a `v1` git tag exists
locally, but the session proxy refused to push tags).

- **v1**: the first story, photos on a pale lilac liquid fitted to the reference video. The design
  notes below under "Design direction (v1)" are about it.
- **v2** (current): the story opens on Earth, there are no threads at all (the user dislikes
  them), and there is no background liquid: the glass orbs are the liquid themselves, in the
  style of a screenshot the user shared (fisheye photo orbs with a soft glow in their own
  colours). See "v2" below.

## v2

- Story (`OnboardingStep.v2`, scenes in `OrbitChoreography`, "MARK: v2 scenes"):
  1. `.planet` "Your world": Earth alone, big, swelling in with a bounce.
  2. `.rise` "It starts with you": Earth shrinks to a planet at the bottom of the stage (clear of
     the footer) and you bud out of its surface: a droplet forms on it, Earth's outline stretches
     into a pear, and you pinch off with a bounce.
  3. `.gather` "Your people find you": six friends bud out of Earth one by one and settle just off
     your edge, so the glass melts into a neck between each of them and you.
  4. `.orbit` "Your world, in orbit": friends glide into two tall elliptical orbits around you,
     inner clockwise, outer the other way, overlapping at the sides so they melt into each other
     as they pass. Earth, now small, orbits you too: the world that was huge on page 1.
  5. After "Get started": everything melts back into Earth, which swells to page 1's size, so a
     screen recording loops.
  The user wants something unique here, not the nine-photo ring; don't bring the ring back for v2.
- Rendering (`Orbit/Bubbles/GlassLiquid.swift`, shader `glassLiquid` in `Liquid.metal`): every
  photo is drawn flat 1.15x its orb (feathered beyond the orb's edge), and the shader turns the
  layer into glass: a smooth union of the orbs (`blend` 12: orbs closer than about 8pt melt
  together), a sphere-shaped surface, a fisheye lens (`lens` 0.42), light (a pale rim, a top
  sheen, a glint, a bright crescent along the bottom) and a glow outside in each photo's own
  colour. The glow colour is the most colourful tone near the photo's rim at saturation 0.38 and
  full brightness: a grey glow on white read as a drop shadow, so it is never grey or dark.
- Stacking in v2: smaller orbs on top, so a bud is a droplet forming on its parent's surface;
  bubbles melting away go underneath everything (`RenderedBubble.isLeaving`).
- Engine features added for v2: per-bubble orbits (`BubbleTarget.orbitRate`, `orbitCenter`,
  `orbitStretch`), buds that start from the parent's surface (`budsFromSurface`), and bouncy
  arrivals for appearing bubbles marked `jelly` (`SpringCurve.budBouncy`, `inflateBouncy`).
- Earth is still the NASA photo (the user said to keep it for now); outside its disc the photo is
  filled with pale blue so no black shows in the glass.

## Design direction (v1)

- Light, flat `#FAFAFA` canvas. SF Pro Rounded everywhere (`.fontDesign(.rounded)`). Bluish
  lavender liquid. The bubbles are the only color on screen.
- Top: back chevron and "Skip" in a slim row, then a centered title (30pt semibold) and one-line
  gray subtitle. Bottom: small page dots and one ink pill button ("Continue", then "Get started").
- Liquid: the reference's effect, measured on a frame of the user's reference video. Shape fitted
  to its outline at every angle (`GooLayer.softness` 10.55, `haloWidth` 9.7 on a big photo, so
  the band around the ring is as thick as the reference's). Edge: `edge` 0.06, about 2pt, picked
  by the user ("variant C"). Measured through the video's own blur the reference's edge is 7pt,
  but on a sharp screen a 7pt fade next to sharp photos read as haze (twice), because in the
  video everything is equally soft. Scallops between neighbours, flat inside, no lighting. Lilac
  #EDDDFA, the reference's flat interior. Re-measure rather than retune by eye, and compare at
  device resolution. One pale tint per crew (lilac, butter, sky), blending where they meet.
- Photos: big, candid, warm (Unsplash), each a glass orb (the `glassOrb` shader in `Liquid.metal`,
  `PhotoStyle.glass`, inspired by the Wabi app the user showed): the photo sits a little behind a
  glass sphere, gently magnified in the middle and bending round at the rim, with a soft window
  reflection on the top rim, a small glint at the top left and a bright crescent at the bottom.
  No shadows, no dark rim. The older look, a sharp photo under a feathered mask
  (`PhotoStyle.mask`, `SoftPhoto`), stays available: triple-tap the onboarding screen in a debug
  build to switch. Neighbouring photos never overlap: about 2pt apart, like the reference.
- Motion: the user now wants the reference's bounce (overshoot on arrivals and on the bloom),
  smooth elsewhere. Earlier "no bouncy springs" is superseded; still no jittery or rubbery idle.

Tried and rejected; don't bring these back: emoji avatars, studio headshots, dark mode, aurora or
mesh-gradient backgrounds, glass chips, story-style progress bars, heavy headlines with an accent
colored word, a round arrow CTA with a progress ring, a bottom-left paragraph, halos or vignettes
that read as drop shadows, gel or glass lighting on the liquid (tried in a mock, read as a drop
shadow), spread-out layouts with small photos in a big body of liquid, and copying the reference
video's layouts one to one.

The user's original reference was an Apple Photos-style "Memories" screen: clusters of photo
bubbles in soft pastel liquid with blurred photo edges. They love its liquid quality and blurred
edges, but wanted an original story, which is the current one.

## The v1 story (one scene per page)

1. `.you` "It starts with you": one big bubble (you), outline slowly undulating.
2. `.bump` "Bump to connect": a friend drifts in from the right, collides and fuses with you
   (jelly spring), then you separate still joined by a liquid thread. Two keyframes.
3. `.circle` "Your circle grows": three friends bud out of each of you; each bud's neck stretches
   into a thread instead of snapping, making one connected liquid network.
4. `.world` "Your world, in orbit": everything drains into one drop (keyframe 1), which blooms into
   the ring: nine glass orbs (radius 40.7, evenly spaced on a ring of radius 121.8, so neighbours
   are 2pt apart), empty middle, slowly turning (keyframe 2). Earth is out of this scene for now (its dark NASA rim); the pastel globe can
   return to the middle later.
5. `.collapse` after "Get started": everything melts into Earth, which shrinks to nothing, then the
   placeholder home screen plays `.world` again.

## Code map

- `Orbit/Bubbles/BubbleEngine.swift`: pure, time-based engine. Bubbles are closed-form springs from
  their current pose to a target, so interruptions never jump; hidden bubbles ride inside their
  `anchor` bubble, which is what makes buds come out of a moving parent. Also threads (with a
  strength spring) and optional labels.
- `Orbit/Bubbles/OrbitChoreography.swift`: the layouts per scene, as keyframes, in a 372 x 480
  reference space centered on the stage. Bubble 0 is Earth, 1 you, 2 the friend you bump, 3-5
  your friends, 6-8 theirs, 9 one more for the ring.
- `Orbit/Bubbles/BubbleStage.swift`: the view. `GooLayer` draws the liquid with the `liquid` Metal
  shader (`Orbit/Bubbles/Liquid.metal`) through `.colorEffect`: discs and capsules with soft
  shoulders summed into one field, cut at 0.5 over a short ramp; the preview tool mirrors the same
  formula. Photos
  are separate views on top, layered by size (Earth just above the liquid, under everyone). The
  stage is laid out in a slot between header and footer but draws full screen.
- `Orbit/Bubbles/SpringCurve.swift`: spring presets.
- `Orbit/Components/BubbleFaces.swift`: `PhotoStyle`, `GlassOrb` (applies the `glassOrb` shader),
  `SoftPhoto` (the feathered mask), `AvatarFace`, `EarthFace`.
- `Orbit/Onboarding/`: copy (`OnboardingStep`), screen (`OnboardingView`), controls.
- `Orbit/Theme/Theme.swift`: colors, including the liquid's light, base, deep and shade.
- `Orbit/Assets.xcassets`: `earth`, `friend-1` (you) to `friend-9`.

SwiftUI gotchas learned on device:

- The old Canvas approach (blur, then `alphaThreshold`) is what made the liquid harsh: a hard cut
  edge, an opaque fill and painted-on highlights. Don't go back to it; the shader's threshold is a
  soft ramp computed per pixel, not a filter.
- Any view-level blur on the goo beyond ~1pt makes the rim fade out like a drop shadow.
- Stacking: photos are ordered by `RenderedBubble.depth` (the animated size without the idle
  breathing, id as tie-break). Ordering by the breathing radius made equal photos that overlapped
  swap places every second or so (the user saw it as "z-index shifting").
- The shader can't be compiled in a cloud session (no Metal toolchain). Keep `Liquid.metal` simple
  and standard, and mirror any change in `tools/preview/render.py` (`shoulder`) so the preview stays
  truthful.

## Verifying without Xcode

- `swiftc -parse` each file for syntax.
- `SWIFTC=/path/to/swiftc tools/engine/run.sh` compiles the engine and choreography against a small
  SwiftUI stand-in, runs checks (scenes settle on target and fit the stage, no NaN or jumps across
  interrupted transitions, which pairs fuse at rest, thread timing versus neck release), and
  records a scripted run. On Linux, get a toolchain from download.swift.org
  (for example swift-6.1.2-RELEASE-ubuntu24.04).
- `tools/preview/run.sh` (v1) or `VERSION=v2 tools/preview/run.sh` turns that recording into a motion preview video (needs python3 with
  Pillow and NumPy, ffmpeg). It approximates the real rendering (Nunito font, approximate blur),
  so it's for judging layout and motion. Keep its copy and timings in sync with
  `OnboardingStep.swift` and `tools/engine/record.swift`.

## Open items

- v2 was just built; waiting on the user's first Simulator recording of it. The `glassLiquid`
  shader has never been compiled (no Metal toolchain in cloud sessions).
- Globe: the NASA Earth photo has a dark rim and the user doesn't like it. Plan: generate a pastel
  lavender world-map texture with Magnific (uses the user's credits, so ask first) and spin it on a
  real 3D sphere (SceneKit) inside the Earth bubble. The user chose to decide this later.
- Page 1 uses a stock photo as "you"; the real app would use the user's own selfie.
