# VibeOS

**AI-native Linux distribution.** Ubuntu 24.04 LTS + KDE Plasma 5.27 + Vibbey (local AI assistant) + Claude Code baked in.

Download → install in 10 minutes → start coding with Claude in 5 more.

**Status**: v2.0.0 in active development. v1 (Kubuntu 22.04 + Cubic build) is archived at tag `v1.0.4.3-final` and under `archive-v1/` for reference.

---

## Download

```bash
# ISO (hosted on iso.mwmai.no + GitHub Releases mirror)
curl -LO https://iso.mwmai.no/vibeos-v2.0.0.iso
curl -LO https://iso.mwmai.no/vibeos-v2.0.0.iso.sha256
curl -LO https://iso.mwmai.no/vibeos-v2.0.0.iso.asc

# Verify signature (D7C1 0B36 D2A7 CC98 253E A01D 8F08 022E 65BC 5F8F)
gpg --keyserver keyserver.ubuntu.com --recv-keys 8F08022E65BC5F8F
gpg --verify vibeos-v2.0.0.iso.asc vibeos-v2.0.0.iso
sha256sum -c vibeos-v2.0.0.iso.sha256
```

Write to USB with `dd`, Ventoy, or Balena Etcher. Boot, pick disk, wait ~5 minutes.

### apt updates (post-install)

VibeOS ships the apt repo pre-configured. `sudo apt update && sudo apt upgrade`
pulls security patches from Ubuntu Noble + any VibeOS-specific fixes from
`repo.mwmai.no`. No manual repo setup needed.

To add the VibeOS apt repo to a vanilla Ubuntu 24.04 install:

```bash
curl -fsSL https://repo.mwmai.no/vibeos.gpg \
  | sudo tee /etc/apt/trusted.gpg.d/vibeos.asc >/dev/null
echo 'deb [signed-by=/etc/apt/trusted.gpg.d/vibeos.asc] https://repo.mwmai.no/ noble main' \
  | sudo tee /etc/apt/sources.list.d/vibeos.list
sudo apt update
```

---

## What's in the box

- **Ubuntu 24.04 LTS (Noble)** — supported until 2029, kernel 6.8+
- **KDE Plasma 5.27** (LTS) with 4 selectable themes: Pacific Dawn (default), Outrun Boulevard, Miami Pastel, Neon Grid (legacy)
- **Vibbey** — local AI assistant via Ollama (`qwen2.5:3b` baked) + Groq cloud fallback
- **Claude Code** pre-installed. First-boot wizard: paste API key → desktop shortcut ready
- **Developer baseline**: zsh + oh-my-zsh, VS Code + Kate, Firefox (Mozilla PPA, not snap), Node 20, Python 3.12, Flatpak + Flathub
- **Updates**: apt repo at `vibeos.mwmai.no/apt` — security patches from Ubuntu + VibeOS-specific packages

---

## Build it yourself

```bash
git clone https://github.com/Matswm86/vibeos.git
cd vibeos
mkosi build     # ~10 minutes, produces vibeos.iso
./scripts/qemu-boot.sh vibeos.iso   # smoke test in QEMU
```

Full docs land in `docs/building.md` on Day 1.

---

## Repo layout

```
.
├── mkosi/                  # Declarative build config (Ubuntu base → ISO)
├── packages/               # Source trees for our .debs
│   ├── vibeos-desktop/     # Branding, themes, wallpapers
│   ├── vibeos-vibbey/      # AI assistant + systemd service
│   └── vibeos-claude-code/ # Claude Code CLI + setup wizard
├── themes/                 # 4 KDE Look-and-Feel packages
├── wallpapers/             # 3+ per theme
├── vibbey/                 # Python source for Vibbey
├── calamares-config/       # Opinionated installer config (auto-partition)
├── apt-repo/               # reprepro config for vibeos.mwmai.no/apt
├── landing/                # vibeos.mwmai.no/ static site
├── docs/                   # User + developer documentation
├── moodboards/             # Design exploration (v2 picked Pacific Dawn)
├── .github/workflows/      # CI: mkosi build + QEMU smoke test per push
├── archive-v1/             # v1 (Kubuntu 22.04 era) — reference only
├── v2-plan.md              # 6-day build plan with exit criteria
└── README.md               # you're here
```

---

## Contributing

Not yet accepting external contributions — v2.0.0 needs to ship first. Issues welcome for bugs / feature requests.

---

## License

See `LICENSE`. VibeOS-specific code is MIT. Ubuntu components retain their upstream licenses (GPL, etc). Full third-party notice lands in `docs/NOTICE.md` on Day 6.
