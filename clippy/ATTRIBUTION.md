# Vibbey — third-party asset credits

## `clippy.glb`

- **Title**: Rigged Microsoft Clippy/Clippit! (Fbx and Blend)
- **Author**: [Freedumbanimates](https://sketchfab.com/Freedumbanimates)
- **Source**: [Sketchfab](https://sketchfab.com/3d-models/rigged-microsoft-clippyclippit-fbx-and-blend-48ae83c5d91e4081b7d23076fdeec5bd)
- **License**: [Sketchfab Standard](https://sketchfab.com/licenses)

### What we use

The model is rigged (1 skeleton, 7 meshes, 58 nodes) but ships with **zero baked animation clips**. VibeOS animates it programmatically via root-transform bob and sway in `clippy/static/main.js`. Proper bone animations (waves, head tilts, "thinking" poses) are v0.5 work.

Embedded textures were stripped from the original Sketchfab export (7.75 MB → 1.13 MB of mesh data only) following the `feedback_audit_glb_embedded_textures.md` lesson from the MWM-AI workspace. This is intentional — the flat-shaded model is lit in Three.js with strong magenta + cyan directional lights so it reads as a "neon statue," which matches the VibeOS Neon Grid aesthetic.

### Attribution obligation

The Sketchfab Standard license requires crediting the author in any redistribution. This file satisfies that requirement. In addition, the "About Vibbey" modal inside the Vibbey window footer shows the same credit to the end user (`clippy/static/index.html` → `#about-modal`).

## Fonts (Phase C — theme pack)

Planned for v0.4.0 ISO but not yet bundled in v0.3.x:

- **Orbitron** — display font, SIL Open Font License 1.1, by Matt McInerney
- **JetBrains Mono** — monospace font, Apache License 2.0, by JetBrains
- **VT323** — terminal retro font, SIL Open Font License 1.1, by Peter Hull

All three are redistributable under permissive terms and will be shipped inside `/usr/share/fonts/vibeos/` in the ISO.

## Theme forks (Phase C)

- **Yaru** (base GTK theme) — GPL-3.0, by Canonical / Ubuntu community
- **Tela-circle** (base icon theme) — GPL-3.0, by vinceliuice
- **Bibata Modern Ice** (cursor theme) — GPL-3.0, by Kaiz Khatri

The VibeOS forks (`VibeOS-Neon`, `VibeOS-Icons`) retain the upstream licenses and are released under GPL-3.0.
