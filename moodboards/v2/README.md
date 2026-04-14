# VibeOS v2 — Moodboards

Three aesthetic directions. Pick one (or remix) before code starts.

Open the SVGs in Firefox/Chrome (they're 3840×2160 so they render at full desktop size).

---

## ① Pacific Dawn — `concept-1-pacific-dawn.svg`

**Vibe**: sunrise over the ocean, warm cream base, soft pink/orange mountains, optimistic and wide-open. White-dominant — desktop chrome looks mostly white with pink/orange accents on active widgets.

**Feels like**: opening your laptop at 7am in Big Sur, coffee steaming, the day is going to go well.

**Good for**: people who stare at a screen 8hrs/day. Light mode all the time. Reads as "creative tool" not "gaming rig."

**Tradeoffs**: less dramatic in screenshots. Marketing material needs the wallpaper to carry the vibe; the window chrome is intentionally understated.

Palette: `#FFF4E6` (cream) · `#FF5A8F` (hot pink) · `#FF7A00` (sunset orange) · `#FFB627` (golden hour) · `#2D1B3E` (plum ink) · `#FFFFFF` (surface).

---

## ② Outrun Boulevard — `concept-2-outrun-boulevard.svg`

**Vibe**: 80s synthwave in full commitment — dark purple sky, hot pink horizon, geometric sun with horizontal slits, neon perspective grid receding to vanishing point. Dark-mode by default.

**Feels like**: Miami Vice × Tron × Kavinsky's "Nightcall." Every screenshot screams "I know what I'm doing." Sells itself on social.

**Good for**: dark-mode people, late-night coders, anyone who wants the OS to have identity the moment it's on screen.

**Tradeoffs**: loud. Not for people who want invisible chrome. Light text on dark requires more care with contrast (all our hex choices hit WCAG AA).

Palette: `#1A0933` (night sky) · `#FF006E` (neon pink) · `#FF5A8F` (sunset) · `#FF7A00` (orange) · `#FFB627` (yellow) · `#01F9FF` (cyan highlight) · `#F8F0FF` (soft white text).

---

## ③ Miami Pastel — `concept-3-miami-pastel.svg`

**Vibe**: daytime Miami, art deco, big soft color blobs, palm silhouette, 1987 pool party. Warm cream base with pink/coral/mint circles as design elements, not literal landscape.

**Feels like**: walking through South Beach at noon. More editorial than synthwave, more fun than minimalism.

**Good for**: middle ground between ① and ②. Light but with more personality than Pacific Dawn. Reads distinctive without being loud.

**Tradeoffs**: the palm + circles are abstract — some people will find it childish, others will find it charming. Art deco wordmark placement matters.

Palette: `#FFF4E6` (cream) · `#E9446A` (deep rose) · `#FF6F9E` (pink) · `#FFA26B` (coral) · `#8FE4C0` (mint accent) · `#4A2545` (deep plum text).

---

## `palette-strips.svg`

Side-by-side comparison: color swatches with hex + role labels, plus a mini Konsole-window mockup showing how window chrome would read in each palette. Open this one FIRST to compare without staring at three separate wallpapers.

---

## Decision prompt

Look at all four SVGs. Answer:

1. **Which wallpaper would you want to stare at for 8 hours** — ①, ②, or ③?
2. **Which palette reads most "VibeOS"** to you — same question but for window chrome, not the wallpaper itself.
3. **Remix option**: e.g. "② wallpaper with ③ palette" is valid — the wallpaper and the desktop color scheme don't have to be locked together.

Once you pick, I'll:
- Build the `.colors` / `.kvconfig` / Aurorae theme package from that palette
- Generate 2-3 more wallpaper variants in the same direction (morning/noon/evening of the same scene) so users have picks
- Lock this as the VibeOS v2 visual foundation and start the 6-day build plan

## What's reusable from v1

Keeping, moving to `v2/theming/`:
- Orbitron + JetBrains Mono TTFs (`theming/fonts/`)
- SDDM theme skeleton structure (`theming/sddm/vibeos/`)
- Plymouth theme skeleton (`theming/plymouth/vibeos/`)
- GRUB theme skeleton (`theming/grub/vibeos/`)
- Vibbey Python code (`clippy/`, `onboarding/`) — refactored for single-config-source model
- Kvantum recolor Python helper

Throwing away:
- `chroot-inject.sh` and the Cubic workflow (replaced by declarative mkosi config)
- Custom Aurorae `decoration.svg` (replaced by Breeze-with-VibeOS-colors — proven not to crash)
- The 11-places-hardcoded `gemma3:4b` default (replaced by single `/etc/vibeos/vibbey.conf`)
- Kubuntu 22.04 base (replaced by Ubuntu 24.04 Noble)
