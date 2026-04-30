# VibeOS v2.0.0-rc1 SHIPPED — handoff 2026-04-30

First hardware-validated public release. Successor to the
`handoff-install-fixes-2026-04-29.md` USB-patch session.

## What shipped

- **ISO**: https://iso.mwmai.no/vibeos-v2.0.0-rc1.iso (16.6 GB / 17,810,948,096 bytes)
- **SHA256**: `a6389f23aac00241f58628df5209273d8e496bf5a5539521fb3eebec202d1f01`
- **Tag**: `v2.0.0-rc1` at commit `2dd460a3` on `origin/v2`
  https://github.com/Matswm86/vibeos/releases/tag/v2.0.0-rc1
- **Landing page**: iso.mwmai.no rewritten for v2 (Ubuntu 24.04 framing)
  with prominent post-install-recovery warning block
- **SHA256SUMS** updated to include both v0.4.1 and v2.0.0-rc1
- v0.4.1 still served at `/vibeos-0.4.1.iso` for reference, linked in
  the landing footer

## Hardware validation (MSI laptop, Tiger Lake-H + RTX 3060 Mobile)

- Live USB boots, Calamares completes
- Installed system black-screens on first boot (known)
- `sudo vibeos-recover-bootloader` from the live USB recovers it in
  ~30 sec — copies live ESP `/vibeos/` tree (kernel + initrd +
  microcode + kernel-modules.initrd) to target ESP, patches loader
  entry with correct `root=UUID=`, retypes GPT
- After recovery: F11 boot → NVMe → Plasma comes up green
- User confirmed: "Ok. Got in."
- Full smoke test (titlebars / ping / Vibbey / USB-less reboot) was
  not yet reported back at session end

## Three open items before v2.0.0 final

| # | Item | Effort | Plan |
|---|---|---|---|
| 1 | `vibeos-bootloader-fix.sh` silently fails inside Calamares chroot — that's why the recovery script is needed at all | ~1 hr | Refactor to use the same logic as `vibeos-recover-bootloader` (which runs in live session's normal namespace and works). Stop trying to detect `/dev/disk/by-label/ESP` from inside the chroot — use partlabel via blkid / sgdisk readback instead. |
| 2 | `/usr/share/ollama` chowns to `ollama:ollama` at build time but reverts to `greeter:render` after sddm-greeter UID renumbering | ~30 min | Add a one-shot first-boot systemd service that re-chowns. Or pin ollama UID in `mkosi.postinst.chroot` before sddm gets installed. |
| 3 | `systemd-resolved` not present as a service on installed system despite being in `mkosi.conf` Packages= | ~15 min triage | Probably renamed in Noble. Confirm correct package name; verify it's a service in installed image. |

After all three: rebuild ISO via `scripts/build.sh`, reflash USB,
clean install on MSI, confirm boot from NVMe **without** running the
recovery script, then drop `-rc1` and tag `v2.0.0`.

## mkosi build infra learnings (worth keeping)

- **mkosi 1 TiB default**: without `mkosi/mkosi.repart/` definitions,
  mkosi v26 makes a 1 TiB ext4 root partition for `Format=disk`.
  mkfs.ext4 journal creation fails on any host with <1 TB free even
  though actual content is ~16 GB. Fix is two tiny conf files —
  `00-esp.conf` (512M ESP, vfat) + `10-root.conf` (ext4,
  `Minimize=guess`). Final image lands at 16.6 GiB. Committed in
  `49adc8e`.
- **build.sh requires ~50 GB free** on /home for the transient
  workspace. Empty Trash + clean /home/mats/.cache before kicking off
  if disk is tight.
- **mkosi.output is root-owned** (docker --privileged write). Use
  `udisksctl` or the docker container itself to clean it; don't waste
  time fighting sudo prompts in non-TTY shells.

## Workstation state

- `mkosi.output/vibeos.raw` (17.8 GB, root-owned) still on disk for
  re-upload if anything goes wrong on the VPS. Safe to delete after
  next ISO build supersedes it.
- Live USB at `/dev/sdb` was unmounted cleanly via `udisksctl
  unmount`. The patched-USB approach is now obsolete since fresh ISO
  has all source-side fixes baked in (kwin-x11, partition layout,
  mount.conf, unpackfs, users.conf, mkosi.repart).

## Commits this session (4)

- `0edc6c7` day 10: install pipeline + Plymouth fixes from MSI install validation
- `091bf64` docs(readme): refresh status to v2.0.0-rc1 + document post-install recovery
- `49adc8e` day 10: explicit mkosi.repart definitions to bound partition size
- `2dd460a3` (tag) v2.0.0-rc1

## Lesson worth keeping

The previous handoff said: "produce a readable artifact first, look
at it, then act". Today's session leaned on that — the
`vibeos-triage` script dump caught the install-time bug (no initrd
on target ESP, wrong root=UUID) in one round trip, instead of
guessing per symptom. Bias toward host-side diagnostic dumps when a
working live system is available.

Also: udisksctl beats sudo mount for removable USB. Filed as
`feedback_vps_ops_are_mine.md`-adjacent learning — try unprivileged
tools first before assuming sudo is required.
