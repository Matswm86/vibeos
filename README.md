# VibeOS

**AI-native Linux distribution.** Ubuntu 24.04 LTS + KDE Plasma 5.27 + Vibbey (local AI assistant) + Claude Code baked in.

Download → install in 10 minutes → start coding with Claude in 5 more.

**Status**: v2.0.0-rc1 — installable end-to-end on MSI hardware (validated 2026-04-30). Live ISO boots, installer completes, target system boots into Plasma with Vibbey + Claude Code. **One known wart**: the Calamares-time bootloader-fix script silently fails inside the chroot, so the freshly-installed system needs one post-install recovery command before it'll boot — see [Post-install recovery](#post-install-recovery) below. Fix in flight. v1 (Kubuntu 22.04 + Cubic build) is archived at tag `v1.0.4.3-final` under `archive-v1/`.

---

## Download

v2.0.0-rc1 ISO is the first hardware-validated build. See [Post-install recovery](#post-install-recovery) for the one currently required post-install step.

When the final v2.0.0 ships, it will be at:

```bash
curl -LO https://iso.mwmai.no/vibeos-v2.0.0.iso
curl -LO https://iso.mwmai.no/vibeos-v2.0.0.iso.sha256
curl -LO https://iso.mwmai.no/vibeos-v2.0.0.iso.asc

# Verify signature (D7C1 0B36 D2A7 CC98 253E A01D 8F08 022E 65BC 5F8F)
gpg --keyserver keyserver.ubuntu.com --recv-keys 8F08022E65BC5F8F
gpg --verify vibeos-v2.0.0.iso.asc vibeos-v2.0.0.iso
sha256sum -c vibeos-v2.0.0.iso.sha256
```

Write to USB with `dd`, Ventoy, or Balena Etcher.

### apt updates (post-install, when shipped)

VibeOS will ship with the apt repo pre-configured. `sudo apt update && sudo apt upgrade` pulls security patches from Ubuntu Noble + VibeOS-specific fixes from `vibeos.mwmai.no`.

To add the VibeOS apt repo to a vanilla Ubuntu 24.04 install:

```bash
curl -fsSL https://vibeos.mwmai.no/vibeos.gpg \
  | sudo tee /etc/apt/trusted.gpg.d/vibeos.asc >/dev/null
echo 'deb [signed-by=/etc/apt/trusted.gpg.d/vibeos.asc] https://vibeos.mwmai.no/ noble main' \
  | sudo tee /etc/apt/sources.list.d/vibeos.list
sudo apt update
```

---

## What's in the box

- **Ubuntu 24.04 LTS (Noble)** — supported until 2029, kernel 6.8+
- **KDE Plasma 5.27** (LTS) with 4 selectable themes: Pacific Dawn (default), Outrun Boulevard, Miami Pastel, Neon Grid
- **Vibbey** — local AI assistant. qwen2.5:3b (1.9 GB) + Claude Code 2.1.109 are **baked into the ISO** at build time via `scripts/bake-extras.sh` — no chroot-time downloads, no "silent WARNING" failures
- **Claude Code 2.1.109** pre-installed globally (`/usr/bin/claude`). First-boot wizard asks for your API key
- **Calamares 3.3.5** installer — auto-launches on live-session login with all three partition modes offered (erase / alongside / manual) + a Vibbey install-helper sidebar explaining each choice
- **Developer baseline**: zsh + oh-my-zsh, VS Code + Kate, Firefox (Mozilla PPA, not snap), Node 22, Python 3.12, Flatpak + Flathub
- **Updates**: apt repo at `vibeos.mwmai.no` — security patches from Ubuntu + VibeOS-specific packages

---

## Build it yourself

**Requirements on build host:**
- Docker (the builder image is built from `Dockerfile.builder`)
- Ollama installed + `ollama pull qwen2.5:3b` done
- Node.js + npm (for pre-baking Claude Code)
- ~30 GB free disk during build (builder scratch + 17 GB ISO)
- sudo (for `verify-iso.sh` loop-mount post-build)

```bash
git clone https://github.com/Matswm86/vibeos.git
cd vibeos
git checkout v2

scripts/build.sh
# Pipeline:
#   1. scripts/bake-extras.sh  — pulls qwen model + claude CLI into mkosi.extra/
#   2. scripts/build-deb.sh    — repacks Ollama tarball + builds 3 vibeos .debs
#   3. mkosi build             — assembles the rootfs, writes mkosi.output/vibeos.raw
#   4. scripts/verify-iso.sh   — loop-mounts the .raw and asserts 8 baked artifacts
#                                (hard-fails the build on anything missing)

# Smoke-test in QEMU (headless, 10 min on TCG):
scripts/smoke-test.sh
```

Env vars:
- `SKIP_BAKE=1` — reuse existing `mkosi/mkosi.extra/` (fast iteration on mkosi config)
- `SKIP_DEB=1` — reuse existing `packages/local/*.deb`
- `SKIP_VERIFY=1` — skip post-build assertions (not recommended)

---

## Repo layout

```
.
├── mkosi/                          # Declarative build config
│   ├── mkosi.conf                  # Packages= list + kernel cmdline
│   ├── mkosi.extra/                # Files injected into rootfs (GITIGNORED
│   │   │                           # — populated by bake-extras.sh)
│   │   ├── etc/vibeos/live-session    # Live-ISO marker, stripped by Calamares
│   │   ├── usr/bin/claude             # Claude Code CLI symlink
│   │   ├── usr/lib/node_modules/...   # Claude Code 2.1.109
│   │   └── usr/share/ollama/...       # qwen2.5:3b model + blobs
│   └── mkosi.postinst.chroot       # Hard-asserts baked extras present,
│                                   # wires Calamares autostart, chowns ollama
├── packages/                       # Source trees for our .debs
│   ├── vibeos-desktop/             # Branding, themes, wallpapers, plymouth,
│   │                               # SDDM config, systemd-boot splash
│   ├── vibeos-vibbey/              # AI assistant package (depends on ollama)
│   └── vibeos-claude-code/         # Claude Code wizard + keyring + profile hook
├── vibbey/                         # Python source for Vibbey server
│   ├── server.py                   # HTTP server + /api/chat + /api/calamares-step
│   ├── launcher.py                 # GTK+webkit2gtk window — chat OR --install-helper
│   ├── static/install-helper.html  # 7-step live-install sidebar
│   └── ...
├── calamares-config/               # Installer config
│   ├── settings.conf               # View + exec sequence
│   └── modules/
│       ├── partition.conf          # Erase / alongside / manual all enabled
│       ├── contextualprocess.conf  # Strips live marker + autostart on install
│       └── welcome.conf            # Requirements (15 GB / 2 GB RAM)
├── scripts/
│   ├── bake-extras.sh              # Pre-bakes ollama model + claude CLI
│   ├── build-deb.sh                # Repacks Ollama .tar.zst + builds 3 .debs
│   ├── build.sh                    # Pipeline: bake → deb → mkosi → verify
│   ├── verify-iso.sh               # 8 loop-mount assertions (blocks burn on fail)
│   ├── smoke-test.sh               # Headless QEMU boot → multi-user.target
│   └── qemu-boot.sh                # Interactive QEMU for debugging
├── apt-repo/                       # reprepro config for vibeos.mwmai.no
├── landing/                        # vibeos.mwmai.no landing page
├── keys/                           # Public signing key (fingerprint above)
├── .github/workflows/              # CI: build + test + release
├── archive-v1/                     # v1 (Kubuntu 22.04 era) — reference only
├── v2-plan.md                      # v2 build plan with exit criteria
└── README.md                       # you're here
```

---

## Architecture: live session vs installed system

VibeOS distinguishes live (running off USB) from installed (on disk) via `/etc/vibeos/live-session`.

| State | `/etc/vibeos/live-session` | Calamares autostart | Vibbey chat autostart | Vibbey install-helper |
|---|---|---|---|---|
| Live ISO (USB boot) | present | ✓ on Plasma login | **skipped** (live marker gates it) | ✓ right-docked sidebar |
| Installed system (post-reboot) | **absent** (Calamares stripped it) | skipped | ✓ on first login only | skipped |

The marker file is dropped during ISO build by `scripts/bake-extras.sh` and removed from the target rootfs by the Calamares `contextualprocess` module during install. This is what enables "Vibbey helps during install, then the chat version takes over on the real system" without two separate .debs.

---

## Post-install recovery

After Calamares finishes and you reboot to the NVMe, the system will currently come up to a black screen. This is a known regression in the install-time bootloader fix path: the `vibeos-bootloader-fix.sh` script runs inside Calamares' chroot but can't reliably locate the live ESP from there, so it skips the `/vibeos/` initrd-tree copy and the target ESP ends up with kernel + bogus `root=UUID=` and no initrd lines.

To recover, **boot from the same USB stick**, open Konsole in the live session, and run:

```bash
sudo vibeos-recover-bootloader
```

It auto-detects the target disk (newest install), copies the full `/vibeos/` tree (kernel + initrd + microcode + kernel-modules.initrd) from the live ESP to the target ESP, patches the loader entry with the correct root UUID, reinstalls `systemd-bootx64.efi`, and retypes the GPT root partition. Takes ~30 seconds. Reboot, F11 → pick the NVMe entry, system comes up to Plasma.

If you installed onto multiple disks, the script fixes only the most recently installed one. Run it once per target.

## Known issues (2026-04-30)

- **Install-time bootloader fix is unreliable** (see Post-install recovery above). The recovery script in `/usr/local/bin/vibeos-recover-bootloader` is the documented workaround. Source-side fix is to refactor `vibeos-bootloader-fix.sh` to use the same logic as the recovery script (which runs in the live session's normal namespace and works).
- **`/usr/share/ollama` ownership** — mkosi.postinst chowns to `ollama:ollama` at build time but UIDs get renumbered later when sddm-greeter is added; ends up `greeter:render`. First-boot service re-chown is the planned fix.
- **`systemd-resolved` not present** as a service on the installed system despite being in `mkosi.conf` Packages=. Probable Noble package-name change. Investigate.
- **systemd-boot splash** is stretched on non-1080p displays. Cosmetic, deferred to v2.1.

---

## Contributing

Not yet accepting external contributions — v2.0.0 needs to ship first. Issues welcome for bugs / feature requests.

---

## License

See `LICENSE`. VibeOS-specific code is MIT. Ubuntu components retain their upstream licenses (GPL, etc). Full third-party notice lands in `docs/NOTICE.md` before v2.0.0 ships.
