# Vibbey — visual reference

## `concept.jpg`

Inspiration mockup shared by Mats on 2026-04-09 / integrated on 2026-04-10.

- A 3D paperclip character (Vibbey) in a retro "VibeOS Assistant" window
- Synthwave / terminal-dark aesthetic, cyan + yellow accents
- Speech bubble in the classic Clippy style:
  > *"Hi! I'm Vibbey, your nostalgic local-AI guide! Looks like you're
  > almost set up. Should we configure your memory graph now? [Yes / Later]"*

## How Phase 1 should use it

This is a **direction-setting reference**, not a pixel-perfect target:

- The 3D model is already in the repo at `projects/vibeos/clippy.glb` (408KB,
  glTF 2.0 binary). Phase 1 loads that via Three.js + GLTFLoader.
- Match the window chrome: dark background, subtle cyan glow, yellow title
  accent, classic minimize/close buttons in the top-right.
- Match the speech bubble styling: white rounded rectangle with the tail
  pointing at Clippy, monospace font, `[Yes / Later]` style quick replies.
- Do NOT try to match the specific facial expression from the mockup — that
  comes from whatever animations are baked into `clippy.glb`.

The whole point of this image is: *this is the vibe we're going for*. If the
Phase 1 MVP looks and feels like this screenshot, we're done.
