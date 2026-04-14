# VibeOS v2 — Build Plan

**Draft**. Review, push back, approve. No code until you sign off.

---

## North Star

A Linux distro a normal developer can install in under 10 minutes and start coding with Claude inside 5 more. AI-native from boot. One opinionated default, four themes, zero config rituals.

**Target user**: you, a Claude Code user who wants the machine to be ready, not configured. A curious dev who downloads it because "it looks cool and it has Claude built in."

**Success at v2.0.0**:
- Boot ISO in QEMU → auto-installer runs → reboot → KDE desktop with Pacific Dawn theme → Vibbey greets → "want to set up Claude Code?" → paste API key → `claude` in `~/workspace` works. Zero terminal commands for the user.
- Same flow works on MSI real hardware.
- GitHub Actions green on every push.
- Downloadable from `iso.mwmai.no/vibeos-2.0.0.iso` (~5.5 GB).

**Not in scope for v2.0.0** (future): encrypted home dir, multi-user, secure boot signing, NVIDIA-specific ISO variant, offline Claude Code (Claude requires internet).

---

## Foundation decisions (lock before Day 1)

| Decision | Choice | Why |
|---|---|---|
| Base | **Ubuntu 24.04 LTS (Noble)** | Supported until 2029, modern kernel 6.8+, stable KDE Plasma packages. |
| Desktop | **KDE Plasma 5.27 (not 6)** | Plasma 6 on Noble is newer/less-tested. 5.27 is rock-solid, themes are mature, Aurorae/SDDM docs plentiful. Upgrade path to Plasma 6 in v2.1 once it stabilizes on 24.04. |
| Build tool | **`mkosi`** (systemd-owned) | Declarative YAML config. Reproducible. Runs in CI. No manual Cubic clicking. Alternative was `live-build` — rejected because less active, harder to debug. |
| Installer | **Calamares with opinionated config** | Single-disk auto-partition, preset user = first boot wizard. No interactive module stack. |
| Window deco | **Breeze with VibeOS accent color** | NOT a custom Aurorae SVG. v1 proved custom decorations are fragile. Breeze ships with every KDE install, uses our accent color natively. |
| AI model | **`qwen2.5:3b` baked** (1.9 GB) | Best quality/size. Fits 8 GB USB. Override with env var at build time for `qwen2.5:7b` "Pro" ISO. |
| Config file | **`/etc/vibeos/vibbey.conf`** single source of truth | Every component (server.py, main.js, onboarding, groq_proxy) reads `VIBEOS_MODEL` from here. Fixes the 11-places-hardcoded bug at the root. |
| Update mechanism | **apt repo on `repo.mwmai.no`** | `reprepro` managed. Components: `vibeos-desktop`, `vibeos-vibbey`, `vibeos-claude-code`. Upgradable independently via `apt upgrade`. |
| CI | **GitHub Actions** on `vibeos` public repo | mkosi build + QEMU TCG smoke test per push. ~20 min per run. Free. |
| Release cadence | **apt packages: continuous. ISO: monthly.** | Users get patches daily via apt. ISO is re-spun monthly for fresh installs. |

**Open question for you** — confirm or correct:

1. KDE Plasma 5.27 (stable) or Plasma 6 (shiny, rougher edges)? I recommend **5.27**.
2. Default shell: `bash` (Ubuntu default) or `zsh` (better for devs)? I recommend **zsh with oh-my-zsh preinstalled**.
3. Editor on desktop: `kate` (KDE default) or `vscode` baked? I recommend **both, vscode-insiders not included** (too Microsoft-y for a Claude-native OS).
4. Browser: `firefox` snap (Ubuntu default — slow) or `firefox` deb from Mozilla PPA (fast)? I recommend **Mozilla PPA**.
5. Flatpak support: yes/no? I recommend **yes** — users can install extras via GNOME Software without snap bloat.

---

## Day 0 — Scaffold (2-3 hours)

**Goal**: v1 preserved, v2 directory structure scaffolded, repo tagged `v1-archive` for rollback.

**Tasks**:
- Tag current main as `v1.0.4.3-final` (reference point for everything we keep)
- Create branch `v2` for all work; main stays on v1 until v2 ships
- Move everything in current `projects/vibeos/` → `projects/vibeos/archive-v1/` on the `v2` branch
- New v2 layout at root:
  ```
  projects/vibeos/
  ├── README.md              (product intro, links to docs)
  ├── v2-plan.md             (this doc)
  ├── mkosi/                 (declarative build config)
  │   ├── mkosi.conf
  │   ├── mkosi.postinst.chroot
  │   └── mkosi.extra/       (files dropped into rootfs)
  ├── packages/              (our .deb source trees)
  │   ├── vibeos-desktop/    (branding + themes)
  │   ├── vibeos-vibbey/     (AI service)
  │   └── vibeos-claude-code/(Claude Code CLI wrapper + setup)
  ├── themes/                (4 Look-and-Feel packages)
  │   ├── pacific-dawn/
  │   ├── outrun/
  │   ├── miami/
  │   └── neon-grid/
  ├── wallpapers/            (PNG + SVG, ≥3 per theme)
  ├── vibbey/                (Python source, replaces v1 clippy/)
  ├── calamares-config/      (modules.conf + settings)
  ├── apt-repo/              (reprepro config + pool)
  ├── .github/workflows/     (build.yml, test.yml, release.yml)
  └── archive-v1/            (v1 reference, not in build path)
  ```
- Copy-and-preserve from v1:
  - `archive-v1/theming/fonts/` → `v2 wallpapers/` can reuse TTFs
  - `archive-v1/theming/wallpapers/` → becomes Neon Grid Legacy wallpaper pack
  - `archive-v1/clippy/` → ref material while rewriting `vibbey/`
  - `archive-v1/LICENSE` → keep
- Delete nothing. `archive-v1/` stays in repo for reference.

**Exit criteria**:
- `git tag v1.0.4.3-final` exists on main
- `git checkout v2 && ls projects/vibeos/` shows new layout with `archive-v1/` populated
- `git log --oneline | head` shows clean scaffold commit

**Rollback**: trivial — `git checkout main`, v1 is intact.

---

## Day 1 — mkosi build boots in QEMU (4-6 hours)

**Goal**: A minimal `vibeos.iso` that boots to a Kubuntu-style desktop in QEMU. No branding, no Vibbey yet. Just proof the build chain works.

**Tasks**:
- Write `mkosi/mkosi.conf` targeting Ubuntu 24.04 Noble + KDE Plasma 5.27
- Package list: `ubuntu-minimal`, `kde-plasma-desktop`, `sddm`, `calamares`, `firefox-esr` (from Mozilla PPA), `git`, `curl`, `vim`, `zsh`, `build-essential`
- `mkosi.postinst.chroot`: runs inside built rootfs — set default shell, preload user, etc
- Local test: `mkosi build` on workstation → produces `vibeos.iso`
- QEMU boot test script: `scripts/qemu-boot.sh` — boots ISO with 4GB RAM, GUI window, no network
- Hand-verify: SDDM login works, `vibeos` user auto-logs-in, Plasma desktop loads

**Exit criteria**:
- `mkosi build` completes without errors
- ISO is ~3 GB (no Vibbey/Ollama yet)
- `qemu-system-x86_64 -cdrom vibeos.iso` shows KDE login, logs in, desktop appears
- `screenshot-day1.png` captured and in repo

**Rollback**: Day 1 mkosi.conf works standalone. If Day 2 breaks it, checkout `v2-day1` tag and you have a minimal-but-working ISO.

---

## Day 2 — Pacific Dawn branding + auto-install (5-7 hours)

**Goal**: Themed VibeOS boots, Calamares one-click installer works end-to-end in QEMU.

**Tasks**:
- Build `packages/vibeos-desktop/` as a real `.deb`:
  - Ships `/usr/share/plasma/look-and-feel/org.vibeos.pacific-dawn/`
  - Ships `/usr/share/color-schemes/VibeOS-PacificDawn.colors`
  - Ships 3 Pacific Dawn wallpapers (sunrise / noon / dusk variants — same scene, different times)
  - Ships Plymouth theme, SDDM theme, GRUB theme (all in Pacific Dawn palette)
  - postinst: `lookandfeeltool -a org.vibeos.pacific-dawn`, `plymouth-set-default-theme vibeos`, `update-grub`
- Install the `.deb` via mkosi.postinst.chroot
- Calamares config at `calamares-config/`:
  - Modules: `welcome, locale, keyboard, partition (auto-erase), users (preset vibeos), summary, install, finished`
  - NO `netinstall`, NO `bootloader-choice`, NO manual partitioning screen
  - Branding: VibeOS Pacific Dawn theme, slideshow = Vibbey welcome animation (placeholder PNG for now, v2.1 gets real Vibbey voiceover)
- QEMU install test:
  - Create 30 GB qcow2 disk
  - Boot ISO → click "Install VibeOS" → accept defaults → wait → reboot → see installed desktop
- First-login state: auto-login to `vibeos` user, Pacific Dawn theme active, GRUB themed

**Exit criteria**:
- `mkosi build` → ISO is ~3.5 GB
- QEMU: full install completes without user input beyond "click Install" and "pick password"
- Reboot to installed system → Pacific Dawn visible in SDDM, GRUB, desktop, Plymouth
- Window decorations are Breeze with VibeOS accent — NO missing titlebars (the v1 bug)
- `screenshot-day2.png` captures the installed desktop

**Rollback**: `v2-day2` tag. Working branded ISO without AI.

---

## Day 3 — Vibbey as systemd service + single config (5-7 hours)

**Goal**: Ollama runs at boot, Vibbey opens on first login, greets user, can chat via Groq OR local model. Single config file, no sed patches.

**Tasks**:
- Refactor v1 `clippy/` into `vibbey/`:
  - All components read `VIBEOS_MODEL` + `VIBEOS_GROQ_API_KEY` + `VIBEOS_CLAUDE_API_KEY` from `/etc/vibeos/vibbey.conf`
  - Remove all 11 hardcoded `gemma3:4b` strings — replaced with `os.environ['VIBEOS_MODEL']`
  - Frontend (`main.js`) fetches `/api/config` on load to get the active model — no more client-side hardcoding
- Build `packages/vibeos-vibbey/` .deb:
  - Installs Ollama + pulls `qwen2.5:3b` at build time (baked into ISO)
  - Creates `ollama.service` + `vibbey.service` systemd units (both enabled)
  - Ships `/etc/vibeos/vibbey.conf` with sane defaults
  - First-run desktop autostart opens Vibbey welcome window
- Vibbey welcome tour:
  1. "Hey, I'm Vibbey. I run locally — privacy-safe."
  2. "You can talk to me in Norwegian or English."
  3. "I can open apps, install software, answer questions, walk you through setup."
  4. "Ready to set up Claude Code?" → (Day 4)
- Safety rails: Vibbey's tool execution is allow-list only. No `rm`, `dd`, `mkfs`, `umount`. Destructive ops require KDE KDialog confirmation, not Vibbey-runnable.

**Exit criteria**:
- QEMU fresh install → first login → Vibbey welcome window appears within 5s of desktop load
- `systemctl status ollama vibbey` → both active
- `cat /etc/vibeos/vibbey.conf` → single config visible
- Chat with Vibbey: "what's 2+2?" gets answered via Groq (if online) or local Ollama (always)
- `grep -r gemma3 /usr/share/vibeos` returns nothing (single source of truth)

**Rollback**: `v2-day3` tag. Working ISO with AI, minus Claude Code integration.

---

## Day 4 — Claude Code baked in (4-6 hours)

**Goal**: First-login flow includes Claude Code setup. User pastes API key once, `~/workspace/` is ready, desktop shortcut opens Konsole with Claude running.

**Tasks**:
- Build `packages/vibeos-claude-code/` .deb:
  - Depends on `nodejs (>=18)`
  - Installs `@anthropic-ai/claude-code` globally via npm at build time (baked)
  - Creates `/usr/bin/vibeos-claude-setup` — interactive wizard:
    1. "Do you have a Claude API key?" [Yes / Get one / Skip]
    2. If yes → paste → store in `secret-tool` (KDE keyring)
    3. Create `~/workspace/` with pre-populated `.claude/settings.json` (permissive defaults for a dev machine)
    4. Create desktop shortcut "Start Coding with Claude" → opens Konsole in `~/workspace/` with `claude` running
  - "Get one" option: opens Firefox to `https://console.anthropic.com/account/keys`
- Integrate into Vibbey welcome:
  - After the 4-step tour, Vibbey asks "Set up Claude Code now?" → launches `vibeos-claude-setup`
  - Vibbey can answer Claude Code questions via built-in docs (shipped as `/usr/share/vibeos/claude-code-docs/`)
- Keyring integration via `secret-tool` — Claude Code reads key from keyring on start, not from plaintext file

**Exit criteria**:
- Fresh install → first login → Vibbey welcome → "Set up Claude Code?" → paste test key → "Start Coding with Claude" shortcut appears on desktop
- Click shortcut → Konsole opens in `~/workspace/` → `claude` runs → API key authenticated
- Screenshots captured for all flow steps
- Tested without API key too: graceful "skip" works, shortcut still created, first `claude` run prompts for setup

**Rollback**: `v2-day4` tag. Working ISO with Claude Code optional but integrated.

---

## Day 5 — All 4 themes + polish (4-6 hours)

**Goal**: Pacific Dawn / Outrun / Miami / Neon Grid all selectable. Wallpapers plural per theme. Konsole + Kate + Dolphin all themed. Icons + cursors feel cohesive.

**Tasks**:
- Finish the other 3 L&F packages: `org.vibeos.outrun`, `org.vibeos.miami`, `org.vibeos.neon-grid`
- Wallpaper pack: 3-4 variants per theme (different times of day / moods in same direction)
- Konsole color scheme per theme (4 schemes total)
- Icon theme: Papirus-Dark with VibeOS accent recolor (use v1's `kvantum-recolor.py`)
- Cursor: Bibata-Modern-Ice (all 4 themes share this — no need to ship 4 cursor sets)
- Vibbey command: "switch to outrun mode" → `lookandfeeltool -a org.vibeos.outrun` via allow-listed tool
- Settings → Global Theme shows all 4 with preview thumbnails

**Exit criteria**:
- Open Settings → Global Theme → see all 4 with working previews
- Apply each one → KDE session updates live (no logout)
- "Vibbey, switch to Miami" works
- All 4 themes have Plymouth + SDDM + GRUB variants matching their palette
- Screenshots per theme captured

**Rollback**: `v2-day5` tag. Polished ISO.

---

## Day 6 — CI, apt repo, release (5-7 hours)

**Goal**: Every push to main triggers a full build + smoke test. Apt repo publishes packages. `vibeos-2.0.0.iso` released on GitHub + hosted on `iso.mwmai.no`.

**Tasks**:
- `.github/workflows/build.yml`:
  - Runs on push to main, PR, manual dispatch
  - Builds ISO with mkosi (~10 min on free runner)
  - Uploads ISO as artifact (GHA artifacts expire in 90 days — OK for dev)
- `.github/workflows/test.yml`:
  - Runs after build succeeds
  - Boots ISO in QEMU TCG mode (software emu, ~10 min)
  - Scripted test: SSH into running QEMU → verify `systemctl is-active ollama vibbey` → check `/etc/vibeos/vibbey.conf` → verify `claude --version` in PATH
  - Fails the PR if any check fails
- `.github/workflows/release.yml`:
  - Triggered on git tag `v2.*`
  - Builds ISO → signs it → publishes to GitHub Releases → rsyncs to `iso.mwmai.no/`
  - Also publishes .deb packages to `repo.mwmai.no/` via reprepro
- Apt repo setup on mwmai.no VPS:
  - `/srv/apt-repo/` with `reprepro` managing `noble` distribution
  - Caddy vhost at `repo.mwmai.no` serving the repo
  - GPG key generated, public key at `repo.mwmai.no/vibeos.gpg`
  - First ISO includes `/etc/apt/sources.list.d/vibeos.list` + `/etc/apt/trusted.gpg.d/vibeos.gpg`
- Release notes written for v2.0.0
- README updated with install instructions

**Exit criteria**:
- Push a trivial commit to main → GHA runs build + test → passes
- Tag v2.0.0 → release workflow publishes ISO to GitHub + mwmai.no
- Fresh VM: `apt update && apt upgrade` works against `repo.mwmai.no`
- Real MSI install (you do this one): boot ISO on USB → install → boot → Vibbey + Claude Code work

**Rollback**: if MSI install fails, don't tag v2.0.0 public. Fix, re-test, re-release. Apt repo + CI still valuable even if first ISO has issues.

---

## Risks + mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| mkosi has a rough edge for KDE base | Medium | Day 1 slips 1-2 days | Fallback: `live-build` (older, more docs) |
| KDE Plasma 5.27 on Noble has package conflicts | Low | Day 1-2 | Noble ships Plasma 5.27 by default, well-tested path |
| GHA free runner can't boot full KDE in QEMU | Medium | Day 6 CI weaker | Fallback: build-only CI + weekly cron install test on local rig |
| Ollama binary changes break systemd unit | Low | Day 3 | Pin ollama version in .deb, test upgrade path |
| Claude Code CLI updates break keyring integration | Medium | Day 4 post-ship | Pin version in .deb, lag behind upstream by 1 release |
| Calamares auto-erase bug wipes wrong disk on weird configs | HIGH | catastrophic | Day 2: add confirmation screen showing exact `/dev/...` + size before proceeding. No silent auto-erase. |
| Custom GPG key compromised | Low | apt repo pwned | Offline key, only signing subkey on VPS |
| I get overconfident and ship v2.0.0 without MSI real-install test | Medium | same bugs as v1 | Lock it: no public tag until MSI test passes. Blocking rule. |

---

## What I need from you before Day 1

1. **Answer the 5 open questions** in Foundation (Plasma 5.27 vs 6, shell, editor, browser, Flatpak).
2. **Confirm scope**: is Claude Code baked in (Day 4) required for v2.0.0, or shippable as v2.0.1? I recommend required — it's the core differentiator.
3. **Target date**: is this "start today, ship by end of week" or "weekend project, ship in 2 weekends"? Affects risk tolerance per day.
4. **Infra go-ahead**: OK to add `repo.mwmai.no` and `iso.mwmai.no` vhosts to the VPS Caddy config?
5. **Push-back**: anything in this plan you disagree with? Any step that feels redundant, or any missing step that'll bite us?

Once you answer these 5, I tag `v1.0.4.3-final` and start Day 0.
