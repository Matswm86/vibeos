# Handoff: Install-clone fix + privacy scrub (2026-06-11)

Supersedes `handoff-vibeos-v2-day9-testing.md` (memory dir). Branch `v2`, all commits pushed to github.com/Matswm86/vibeos.

## Symptom (user report, MSI machine)
After installing from USB and rebooting, the machine booted back into the Plasma live-installer session ("install page"), and the Install VibeOS icon did nothing.

## Root causes (all evidence-verified)
1. **contextualprocess.conf written in shellprocess syntax** → Calamares silently ignored it → live artifacts (live user, SDDM autologin override, installer autostart, install icons, live sudoers) were rsynced onto the target verbatim. The installed system WAS a working install that looked identical to the live USB. THE core bug.
2. **Dead install icon**: installed system has no `/etc/calamares` (correctly excluded), Calamares exited instantly; launcher logged to tmpfs `/tmp` only, no dialog. Silent.
3. **`useradd -G "$GROUPS"` bash trap**: `GROUPS` is a read-only bash special var → live user ended up in group root(0), not reliably in sudo.
4. **Boot-order ambiguity**: MSI has TWO disks with PARTLABEL `vibeos-root` (stale April install on Micron nvme1n1 + new on Kingston nvme0n1); `bootctl --no-variables` created no NVRAM entry, firmware free to boot the old disk.
5. The May 29 install itself SUCCEEDED (deploy log on USB ESP proves it).

## Fixes (commits e30faf0, 8b06df7, e1c0790, 1b3f3e5)
- contextualprocess DELETED → single script `scripts/vibeos-target-cleanup.sh` (baked at `/usr/local/sbin/`), runs post-unpackfs (strip: userdel vibeos, remove 6 live artifacts, hard-FATAL if user persists) + again as last sequence step with `--verify` (install fails loudly if any artifact remains).
- displaymanager module added + `doAutoLogin: true` in users.conf → new user gets SDDM autologin on target.
- GROUPS bug fixed (explicit EXTRA_GROUPS loop + build assertion vibeos ∈ sudo).
- launch-calamares rewritten: persistent log `~/.cache/vibeos-launch-calamares.log`, kdialog/zenity errors, "already installed" guard, single-instance guard, sudo→pkexec fallback.
- vibeos-bootloader-deploy.sh: `bootctl install` WITH NVRAM first (Linux Boot Manager first in BootOrder), `--no-variables` fallback.
- verify-iso.sh: 13 checks incl. regression guards for all of the above. ALL GREEN on shipped build.

## Privacy gate (WIDENED 2026-06-11)
Old gate: `grep -ao "Mats Mj"` empty. **New gate (use this):**
```bash
strings -n 7 mkosi.output/vibeos.raw | grep -m3 -e "Mats Mj" -e "matswm86"   # must print nothing
```
(`grep -ao` directly on the 16.6G raw buffers GB-long lines → earlyoom kills it, exit 137. Always go via `strings`.)
- Real name leaked via deb `Maintainer:` fields → fixed e1c0790 (control+changelog → `VibeOS Project <vibeos@mwmai.no>`).
- Personal email leaked via 12 wallpaper/look-and-feel metadata files → fixed 1b3f3e5.
- **Flashed USB image (built 08:51): name-CLEAN, email still present** (3 theme-metadata hits) — fine for Mats's own MSI, NOT for publication.
- ~~rc1 ISO live at iso.mwmai.no leaks real name~~ **RESOLVED 06-11**: Day-9 claim was STALE. Both ISO binaries were already absent from the VPS (404, no .iso anywhere on disk; GitHub has no releases, 2GB asset cap means the 16.6G ISO never lived there). Only the download PAGE still advertised rc1 → replaced with placeholder ("downloads temporarily offline"), backups at `/var/www/iso/{index.html,SHA256SUMS}.bak-2026-06-11`. Re-publish only a post-1b3f3e5 build (debs already rebuilt in `packages/local/`) after the widened gate passes.

## State at handoff
- USB (SanDisk Ultra 28.6G, by-id `usb-SanDisk_Ultra_4C530001170104122363-0:0`): flashed with the 06-11 08:51 build, all 13 verify checks green.
- MSI next steps: boot USB → install (recommend Erase on Kingston 2TB nvme0n1) → reboot WITHOUT USB. NVRAM entry should boot the new disk first. Stale April install on Micron nvme1n1 can be wiped after.
- Failure forensics if needed: `/vibeos-deploy-debug.log` on USB ESP; on installed disk `/var/log/vibeos-target-cleanup.log` + `/var/log/vibeos-bootctl-install.log` + `~/.cache/vibeos-launch-calamares.log`.
- Goal reminder: vibe-coder OS, Vibbey agent (qwen2.5:3b via ollama, baked), plug-and-play Claude suite (CLI 2.1.172 baked globally).
