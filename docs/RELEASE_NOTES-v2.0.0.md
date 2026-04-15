## VibeOS v2.0.0

First stable release of the v2 series — a full rewrite on mkosi +
Ubuntu Noble + KDE Plasma, replacing the v1 Cubic-based Kubuntu build.

### Highlights

- **Ubuntu 24.04 LTS** base (supported until 2029), kernel 6.8+.
- **KDE Plasma 5.27** (LTS) desktop.
- **4 Global Themes** switchable from Settings or by voice:
  - Pacific Dawn (default) — warm sunrise
  - Outrun Boulevard — synthwave magenta + cyan
  - Miami Pastel — peach + coral + teal
  - Neon Grid — black chrome + neon green
- **Vibbey**, the local AI assistant:
  - Ollama-backed with `qwen2.5:3b` baked into the ISO
  - Groq cloud fallback for heavier prompts (optional API key)
  - Voice command `switch to <theme-name> mode` live-switches the
    Global Theme
- **Claude Code** pre-installed with first-boot wizard (kdialog
  prompts for API key, stores in KDE Wallet, creates
  `~/workspace/` + desktop shortcut).
- **Calamares installer** with Pacific Dawn branding and a
  confirmation screen before any disk is touched.
- **apt repo** at `vibeos.mwmai.no` pre-configured — `apt update`
  works out of the box for VibeOS-specific updates.

### Download

- ISO: <https://iso.mwmai.no/vibeos-v2.0.0.iso>
- SHA256: <https://iso.mwmai.no/vibeos-v2.0.0.iso.sha256>
- Signature: <https://iso.mwmai.no/vibeos-v2.0.0.iso.asc>

GitHub Releases mirror: see the assets attached to this release.

### Verify

```bash
gpg --keyserver keyserver.ubuntu.com --recv-keys 8F08022E65BC5F8F
gpg --verify vibeos-v2.0.0.iso.asc vibeos-v2.0.0.iso
sha256sum -c vibeos-v2.0.0.iso.sha256
```

Signing key fingerprint:
`D7C1 0B36 D2A7 CC98 253E  A01D 8F08 022E 65BC 5F8F`

### Install (USB)

```bash
# Replace /dev/sdX with your USB device. Double-check with `lsblk`.
sudo dd if=vibeos-v2.0.0.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

Boot the USB, pick your disk in Calamares, wait ~5 minutes, reboot.

### Known issues

- SDDM login screen is themed Pacific Dawn only (other themes apply
  inside the session). Fix scheduled for v2.0.1.
- First `ollama pull` after install re-downloads `qwen2.5:3b` if the
  model cache was not preserved during install. Working as designed;
  ~2 GB download.
- GHA test workflow only verifies multi-user.target; full Plasma boot
  test runs on self-hosted runner nightly.

### Changelog

See [`debian/changelog`](../debian/changelog) and the commit range
[`v1.0.4.3-final...v2.0.0`](https://github.com/Matswm86/vibeos/compare/v1.0.4.3-final...v2.0.0)
for the full list.

### Upgrading from v1

v2 is **not** an apt upgrade path — it's a fresh install. v1 users
should back up their home directory, install v2 from USB, and
restore. `/home` is preserved if installed to the same disk with
Calamares' "erase disk" unchecked.
