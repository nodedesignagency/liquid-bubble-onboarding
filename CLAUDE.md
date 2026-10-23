# Orbit: liquid bubble onboarding

SwiftUI onboarding (iOS 17+, no dependencies) for Orbit, a friend-circle app in the spirit of
Bump and Snapchat, told with liquid "metaball" bubbles. See README.md for the overview.

## Working with the user

- Keep working on branch `claude/nice-cori-ypokiu`: commit and push every change there.
- **End every reply with this exact command** (the user asked for it every time, even when
  nothing changed), so they can pull and run:

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

## Three versions

The app holds three onboardings. The home screen's "Replay v1/v2/v3" pick which one plays
(remembered across launches under `onboardingVersion.3`, renamed so v3 played once on devices that
remembered v2; v3 is the default). Work on v3 unless the user says otherwise, and leave v1 and v2
as they are: they are saved previous directions (v1 is commit 86737e4; a `v1` git tag exists
locally, but the session proxy refused to push tags).

- **v1**: the first story, photos on a pale lilac liquid fitted to the reference video, in pages.
  The design notes below under "Design direction (v1)" are about it.
- **v2**: one screen in the style of the Wabi app (a video the user shared): swipe up a big glass
  Earth and your friends bubble out of it as liquid glass. The user said it was "way better" but
  looked the same as Wabi, so it is saved as is. See "v2" below.
- **v3** (current): dark; pull back from a real city to a glowing holographic globe (after the
  Bump app's Earth zoom and the Blink app's globe), friends pinned on it lift off into orbit,
  joined to Earth by necks of liquid glass (after the AiOS concept). See "v3" below.

## v3

How it got here: the user asked for something "out of the box", not like Wabi: keep the base idea
(Earth, friends bubbling out as liquid), take the Bump app's Earth zoom (ideally reversed: start
zoomed in, pull back to Earth), Earth in the middle with 4-5 people popping out, more out of those.
The first v3 (white page, flat grey liquid, map shrunk into a glass orb) they called "way way
better", but: the jump from black space to the white page was "very bad", MapKit's tiles didn't load
in time so the zoom was grey for three seconds, Earth went blurry once it shrank (Liquid Glass over
a scaled map), and the flat liquid looked "cluttered and cheap". Their next references: Blink (a
glowing holographic globe on black with friends pinned on it) and the AiOS concept (a dark dot
grid, a central orb with four satellites joined by tapered liquid stems), "but liquid glass instead
of flat colour". Not used yet: a Recollect paywall where thumbnails burst out of an icon in 3D.

- Screen (`Orbit/Onboarding/WorldOnboardingView.swift`): dark all the way (`Theme.worldCanvas`
  #040406, white type, `preferredColorScheme(.dark)` for v3 in `RootView`). The sequence waits on
  loading, then everything after the handover is a function of time:
  1. The city: a live `MKMapView` (`CityMapController`, realistic elevation) at the Eiffel Tower
     (1.5 km, pitch 62, heading 330), under a dark cover that fades once MapKit reports the city
     fully rendered (at most 6 s). As soon as the map has a size it estimates its scale and
     `ZoomImagery` fetches satellite snapshots of the same spot (`MKMapSnapshotter`), each 3.2x
     wider, up to 4,600 km (the first 1100pt at 3x, the rest 800pt at 2x). The city holds at least
     1.5 s, and until the snapshots are in (at most 3.5 s more).
  2. Rise (1.3 s, UIKit camera animation): pitch to 0, distance 2.6 km. Measure metres per point.
  3. Zoom out (3.6 s, `ZoomPath`): scale eased in log space from the handover to the globe at
     rest. `ZoomStack` draws the snapshots (the finest that covers the screen plus finer ones over
     it, each feathered from 80% of its radius), turned by the map's heading and unwinding to
     north up. When the coarsest snapshot stops covering, they dissolve into the globe, which
     then drifts from the screen's middle to its place and turns from Paris to 25N 12E.
  4. "Everyone you love, / in one orbit." under the globe; pins (`.pins`): Earth's glass seeps
     out from under the globe and the four friends pop up as pins on their cities (London,
     Dubai, Nairobi, Lagos; `OrbitChoreography.friendHomes`), with a white edge like Blink's.
  5. Lift-off (`.bloom`): each pin grows into a friend in a ring of glass, in orbit at a corner
     round Earth on its city's side, a neck of glass stretching from Earth's ring to it
     (`GlassNeck`, the classic metaball connector), bobbing so the necks breathe. The dot grid
     fades in, the copy becomes "Meet Orbit." / "Your friends, always within reach.", then a
     white "Continue with Apple" and a glass "Continue with phone number".
  6. Drag around Earth spins the friends (`SpinDial`) and turns the globe on its axis; it also
     drifts 1.2 degrees a second. "Continue": friends melt into Earth, the zoom runs backwards
     (3 s) into the snapshots and the map, the map tilts back up to the tower, then home.
- Globe (`Orbit/Bubbles/HoloGlobe.swift`, shader `holoGlobe`): drawn per pixel, so it's sharp at
  any size. Geometry `GlobeMath` (pinhole camera, `distance` in Earth radii; 9 at rest, globe
  radius 84). Continents from `land-sdf` (a 4096x2048 signed distance field of Natural Earth's
  10m land, built by `tools/globe/landsdf.py`; two calibration blocks in its top-left corner give
  the coast level and scale, so colour conversion can't move the coastline). Pearl land with a
  pastel sheen (pink, lilac, sky), raised (lit shore, shadowed sea behind), indigo sea, cool rim,
  violet aura.
- Glass (`Orbit/Bubbles/GlassNetwork.swift`): Earth's ring (radius 91 round the 84 globe), each
  friend's ring (33, photo 28) and the necks, as real Liquid Glass in one `GlassEffectContainer`
  on iOS 26 (each shape in a view sized to its bounds); a dark outline before. Layers: grid,
  zoom, glass, globe (`BubbleStage`'s `centerpiece`), photos.
- Engine additions: `BubbleTarget.popsInPlace` (pins appear on their city, not out of Earth),
  `RenderedBubble.isAppearing` (photos pop only when appearing or leaving, not when a pin grows).
- Mocked first in Python (scratch): four friends read cleaner than five, which crowded the edges.

## v2

- Fixed after the user's recording: at launch Earth swelled out of the middle of the screen and
  bounced down to the dome (now `BubbleStage(startsSettled:)`); on the reveal, Earth's shrink from
  222 to 30 used the 10% bounce and dipped to about 9 before popping back (now any change of size
  over 40% on a `jelly` bubble uses `SpringCurve.swell`).

- Screen (`Orbit/Onboarding/GlassOnboardingView.swift`), canvas `Theme.glassCanvas` (#EDEDEF,
  close to Wabi's #ECECEC):
  1. Gate (`.gate`): "Everyone you love, / in one orbit." at 40% height, Earth as a huge glass dome
     rising from the bottom edge (top at about 70% height), "Swipe up to enter" just above it.
  2. Swipe: Earth follows the finger with growing resistance (`EarthLift`). Letting go above 90pt
     (or a flick) reveals; otherwise it springs back.
  3. Reveal (`.reveal`): Earth flies up into a small orb (radius 30) above the title, stretching
     like a drop as it goes and bending the headline it passes through; the headline is drawn into
     the glass layer for that. Friends and six clear glass droplets bud out of Earth's surface one
     by one into a floating cluster above it, each bobbing on a small circle, so neighbours keep
     melting together and letting go. "Meet Orbit." / "Your friends, always / within reach." fade
     in under Earth, then two glass buttons ("Continue with Apple", "Continue with phone number")
     and a legal line.
  4. "Continue": everything melts back into Earth, which sinks to the dome (the first frame, so a
     recording loops), then the home screen.
- Rendering (`Orbit/Bubbles/GlassLiquid.swift`, shader `glassLiquid` in `Liquid.metal`): photos
  are drawn flat into one layer (95% of the orb, soft edge from 86%; the rim is clear glass), with
  the headline over them. The layer is flattened with `.drawingGroup()` before the shader: without
  it the shader saw each photo on its own and the user saw white squares where photos overlapped.
  The shader: smooth union of the orbs (`blend` 12: orbs closer than about 8pt melt together into
  a neck of clear glass), sphere-shaped surface, fisheye lens (`lens` 0.5), iridescent rim, a fine
  light grey edge, a soft highlight and glint, the bright crescent along the bottom, and a glow in
  each photo's own colour (never grey: grey on light reads as a drop shadow). Moving orbs stretch
  along their motion like drops (`maxStretch` 0.42), photo and glass together; the stage measures
  each bubble's velocity from a snapshot 1/120 s earlier.
- Buttons: `GlassButton`, real Liquid Glass (`.glassEffect`) on iOS 26+, frosted material before.
  Mobbin references for the layout: Dot, Genie, and a clean music app's sign-in screen.
- Stacking: smaller orbs on top, so a bud is a droplet forming on its parent's surface; bubbles
  melting away go underneath everything (`RenderedBubble.isLeaving`).
- Engine features added for v2: per-bubble orbits (`orbitRate`, `orbitCenter`, `orbitStretch`),
  buds from the parent's surface (`budsFromSurface`), bouncy arrivals and shrinks for `jelly`
  targets (`budBouncy`, `inflateBouncy`). The engine check allows v2's Earth fling to move fast
  (up to 24pt per 120 Hz frame); v1 keeps its 12pt limit.
- Earth is still the NASA photo (the user said to keep it for now).
- Tried and dropped in v2: four pages (Earth, rise, gather, orbit), a trailing drop behind Earth
  (it broke off and read as a ghost bubble), and the nine-photo ring (the user wants something
  that doesn't look like the reference).

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

Tried and rejected (for v1; v3 is dark because the user asked for it, after the Blink and AiOS
references); don't bring these back: emoji avatars, studio headshots, dark mode, aurora or
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
  your friends, 6-8 theirs, 9 one more for the ring; v2 adds 10-15, photo-less glass droplets
; v3 uses Earth and 1-4.
- `Orbit/Bubbles/GlassLiquid.swift`: v2's `GlassLiquidLayer` (photo layer, velocities, stretch),
  `EarthLift` (the swipe), `GlassPhoto` (photos at 95% of the orb, glow colours).
- `Orbit/Bubbles/EarthZoom.swift`: v3's city (`CityMapController`), snapshots (`ZoomImagery`),
  `ZoomStack`, `ZoomPath`.
- `Orbit/Bubbles/HoloGlobe.swift`: `GlobeState`, `HoloGlobeView` (the `holoGlobe` shader).
- `Orbit/Bubbles/GlassNetwork.swift`: `WorldGlass`, `GlassNeck`, `WorldPhoto`, `SpinDial`.
- `Orbit/Onboarding/WorldOnboardingView.swift`: the v3 screen, its sequence, copy, `DotGrid`,
  `WorldButton`. `GlobeMath` (the globe's projection) is at the end of `OrbitChoreography.swift`
  so the engine checks can use it.
- `Orbit/Onboarding/GlassOnboardingView.swift`: the v2 screen, its copy, and `GlassButton`.
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
- `Orbit/Assets.xcassets`: `earth`, `friend-1` (you) to `friend-9`, `land-sdf` (v3's continents).

SwiftUI gotchas learned on device:

- The old Canvas approach (blur, then `alphaThreshold`) is what made the liquid harsh: a hard cut
  edge, an opaque fill and painted-on highlights. Don't go back to it; the shader's threshold is a
  soft ramp computed per pixel, not a filter.
- Any view-level blur on the goo beyond ~1pt makes the rim fade out like a drop shadow.
- Stacking: photos are ordered by `RenderedBubble.depth` (the animated size without the idle
  breathing, id as tie-break). Ordering by the breathing radius made equal photos that overlapped
  swap places every second or so (the user saw it as "z-index shifting").
- The shader can't be compiled in a cloud session (no Metal toolchain). Keep `Liquid.metal` simple
  and standard, and mirror any change in the preview tool (`render.py` for v1's `liquid` and
  `glassOrb`, `render_v2.py` for `glassLiquid`) so the preview stays
  truthful.

## Verifying without Xcode

- `swiftc -parse` each file for syntax.
- `SWIFTC=/path/to/swiftc tools/engine/run.sh` compiles the engine and choreography against a small
  SwiftUI stand-in, runs checks (scenes settle on target and fit the stage, no NaN or jumps across
  interrupted transitions, which pairs fuse at rest, thread timing versus neck release), and
  records a scripted run. On Linux, get a toolchain from download.swift.org
  (for example swift-6.1.2-RELEASE-ubuntu24.04).
- `tools/preview/run.sh` (v1, `render.py`), `VERSION=v2` (`render_v2.py`) or `VERSION=v3`
  (`render_v3.py`, which can't draw the map: the zoom is a labelled stand-in) turns that recording into a motion preview video (needs python3 with
  Pillow and NumPy, ffmpeg). It approximates the real rendering (Nunito font, approximate blur),
  so it's for judging layout and motion. Keep its copy and timings in sync with
  `OnboardingStep.swift`, `WorldOnboardingView.swift` and `tools/engine/record.swift`. Pillow 12
  ignores a fill's alpha when drawing text, so `render_v3.py` draws text through a mask.
  `PREVIEW_SCALE=1` renders v3 at half resolution, about four times faster (the video is scaled
  to 600 wide anyway).

## Open items

- v3 was just rebuilt dark; waiting on the user's Simulator recording. Never compiled here:
  watch the `holoGlobe` shader's texture argument, `Path.union`, `GlassEffectContainer`, and
  the MapKit and snapshot calls. On the recording check: does the city wait until it's rendered,
  are the snapshots in by the rise (else the zoom starts from coarser, softer imagery), how sharp
  the zoom's edges are (the outer screen shows coarser snapshots), the dissolve into the globe,
  pins on the right cities, and how the Liquid Glass necks look on the dark grid (and whether the
  globe's aura over them muddies the glass).
- MapKit's Apple Maps logo and Legal link show during the city but not in the snapshots.
  A shipping app must credit the imagery wherever it is shown.
- The Recollect "burst out of the icon in 3D" idea is unused; it could become the bloom's entrance.
- v2's `glassLiquid` shader and `.glassEffect` buttons were confirmed working in the user's
  recording.
- Globe: the NASA Earth photo has a dark rim and the user doesn't like it. v3 replaces it with
  its own holographic globe shader. v1 and v2 still use the photo; the earlier plan for
  them was a pastel world texture from Magnific (the user's credits, so ask first) on a SceneKit
  sphere.
- Page 1 uses a stock photo as "you"; the real app would use the user's own selfie.
