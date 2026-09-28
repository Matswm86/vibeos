# Handoff: Network audit — why the installed MSI has no wifi (2026-08-03)

> **UPDATE 18:30: ALL FIXES SHIPPED + IMAGE REBUILT GREEN.** Commit `a28c13f` on v2
> (pushed). New image `mkosi.output/vibeos.raw` (17.9GB, built 18:20) passed all 20
> verify-iso checks incl. 5 new network/sudo regression guards. A 5th bug found after
> the audit below: **the installed owner account had no sudo** (users.conf
> defaultGroups was Arch-style, no 'sudo') — fixed + fix-forward in target-cleanup.
> Build-host lesson: mkosi stages ~17G in the container's /var/tmp → ENOSPC on tight
> roots; build.sh now supports VIBEOS_SCRATCH + pins --workspace-directory (do NOT
> point scratch at a USB stick — 5x slower). Next: dd to the SanDisk Ultra (by-id
> usb-SanDisk_Ultra_4C530001170104122363), reinstall on MSI (Erase → Kingston),
> reboot without USB, Vibbey onboarding auto-opens, then "Start Coding with Claude".

Audited the 06-11 08:51 USB build (SanDisk Ultra, sdc: ESP + root-x86-64) and current source.
The install itself SUCCEEDED (ESP deploy log 2026-06-11T08:32 "done OK", NVRAM entry, Kingston nvme0n1).
Model qwen2.5:3b IS baked (750/ollama-owned dir hides it from unprivileged `du` — do not re-flag), claude CLI at /usr/bin/claude, autologin config correct.

## 3 image bugs (verified in BOTH source and flashed USB; installed MSI system has all 3)

1. **No `wpa_supplicant` anywhere in the image.** In Noble it is only a *Recommends* of
   network-manager; mkosi installs without Recommends. Firmware (189 iwlwifi + mediatek +
   rtw89 blobs), network-manager, plasma-nm, wireless-regdb are all present — NM just can
   never scan/associate. This alone explains "couldn't find any wifi".
2. **Ethernet dead too.** `/etc/netplan/` is EMPTY, so Ubuntu's stock
   `/usr/lib/NetworkManager/conf.d/10-globally-managed-devices.conf`
   (`unmanaged-devices=*,except:type:wifi,gsm,cdma`) is never overridden → NM ignores wired.
   systemd-networkd is enabled but has ZERO .network files. Result: no connectivity path at all.
3. **No Ubuntu archive apt sources in the image.** Only `vibeos.list` (vibeos.mwmai.no) +
   Mozilla PPA. `sudo apt install wpasupplicant` fails even when online until noble sources
   are added. `ubuntu-archive-keyring.gpg` IS present.

## Rescue on the installed MSI (no rebuild) — run in Konsole

```bash
# 1. Let NM manage ethernet / phone-USB-tether (empty /etc file shadows the wifi-only stock conf)
sudo touch /etc/NetworkManager/conf.d/10-globally-managed-devices.conf
sudo systemctl restart NetworkManager
# → now plug in ethernet cable OR phone with USB tethering; DHCP connects automatically

# 2. Add Ubuntu archive sources
sudo tee /etc/apt/sources.list.d/ubuntu.sources >/dev/null <<'EOF'
Types: deb
URIs: http://archive.ubuntu.com/ubuntu/
Suites: noble noble-updates noble-security
Components: main universe multiverse restricted
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
sudo apt update

# 3. Wifi
sudo apt install -y wpasupplicant iw rfkill
sudo systemctl restart NetworkManager   # wifi networks now appear in the Plasma panel
```

Caveat: if the MSI board has no wifi module, nothing appears even after the fix — check
`lspci | grep -i net` / `ip link` for a wl* device; USB wifi dongle if absent.

## Source fixes for next build (NOT yet applied)

- `mkosi/mkosi.conf` Packages: add `wpasupplicant` (+ `iw`, `rfkill`).
- Ship `/etc/netplan/01-network-manager-all.yaml` (`network: {version: 2, renderer: NetworkManager}`)
  via mkosi.extra — netplan then writes the /run NM override (`unmanaged-devices=none`),
  matching stock Ubuntu desktop; wired + wifi both land in plasma-nm.
- Bake `/etc/apt/sources.list.d/ubuntu.sources` (block above) into mkosi.extra.
- `scripts/verify-iso.sh`: add checks — wpa_supplicant binary present, netplan file present,
  ubuntu.sources present.

## Intended post-install first-boot flow (traced, for reference)

Reboot without USB → firmware boots "Linux Boot Manager" (NVRAM) → systemd-boot →
Plymouth Pacific Dawn → SDDM **autologin** as the Calamares-created user → Plasma →
`/etc/xdg/autostart/vibbey-first-run.desktop` fires (live-session marker stripped on target,
`~/.vibeos/first-run-complete` absent) → **Vibbey onboarding window opens automatically**,
backed by vibbey.service + ollama.service with the baked qwen2.5:3b — works fully offline.
Next step after onboarding = desktop icon **"Start Coding with Claude"**
(`konsole -e /usr/bin/vibeos-claude-start` → setup wizard → key in keyring →
`/etc/profile.d/vibeos-claude.sh` exports ANTHROPIC_API_KEY; workspace template in
`/usr/share/vibeos/claude-workspace-template/`). That step NEEDS internet → blocked by the
bugs above until the rescue is run.

## Still true from 06-11 handoff

- Stale April install on Micron nvme1n1 still carries PARTLABEL `vibeos-root` — wipe it once
  the new install is confirmed booting, or boot-order ambiguity can return.
- This USB build is real-name-clean but personal email remains in 3 theme-metadata files —
  fine for own MSI, NOT for publication (widened privacy gate in 06-11 handoff).
