# VibeOS black-screen-on-first-boot FIXED — handoff 2026-05-29

Closes rc1 open-item #1 (`handoff-v2-rc1-shipped-2026-04-30.md`). The
installed system no longer black-screens on first boot; no manual
`vibeos-recover-bootloader` pass is needed. Rebuilt + verified, not yet
hardware-confirmed on the MSI.

## Root cause (source-verified, not handoff lore)

Boot chain is systemd-boot Type-1 entries only (no UKI; `EFI/Linux` is
empty). The live USB loader entry has **no `root=`** — it relies on the
GPT x86_64-root discoverable-partition type to auto-mount root. But
`partition.conf` (lines 32-36) **deliberately does NOT set that GPT type**
(it "broke X11" on this Calamares build), so the installed disk needs an
explicit `root=UUID=` patched into its loader entry instead.

The job that should do that — `shellprocess@bootctl` →
`vibeos-bootloader-fix.sh` — ran **inside the Calamares chroot**
(`dontChroot: false`). Inside the chroot the live USB ESP is already
mounted busy/read-only in the host namespace, so the script's
`mount -o rw` of the live ESP failed. That mount gates the copy of the
`/vibeos/` kernel tree + loader entries to the target ESP (step B), so
**the kernel was never copied to the target** → systemd-boot with no
bootable entry → black screen.

**Smoking gun:** the fix script writes its own debug log to the live USB
ESP the moment it mounts it. That log was ABSENT from the user's USB ESP
after an install → the script never reached the live ESP at all.

(Two earlier mis-diagnoses, now retracted: it was NOT "efivarfs missing
in chroot", and the target fstab is fine — the triage's `tmpfs /tmp`
fstab was `/mnt/t` = the USB's own rootfs, not the installed disk.
nouveau is also NOT the cause: the live USB + Calamares GUI both run
graphically on nouveau on the MSI RTX 3060.)

## The fix (4 changes, all in repo)

| File | Change |
|---|---|
| `scripts/vibeos-bootloader-deploy.sh` (NEW) → installed to `mkosi.extra/usr/local/sbin/` (root:root 0755) | Host-side deploy. Proven `vibeos-recover-bootloader` logic, adapted to **reuse Calamares' existing target mounts** (findmnt, never re-mounts busy devices) + **blkid fallback** for the root UUID if fstab lacks an ext4 `/` line. Locates target by partlabel `vibeos-root` (NOT `/`, which is the live USB host-side). |
| `calamares-config/modules/shellprocess_bootctl.conf` | `dontChroot: false → true`; calls `vibeos-bootloader-deploy.sh`. Runs in the live namespace where the ESP is mountable — the same namespace the recovery script always worked in. |
| `mkosi/mkosi.postinst.chroot` | chmod 0755 the new deploy script at build time. |
| `scripts/verify-iso.sh` | (a) **passwordless**: re-execs in privileged `vibeos-builder` container as root, `$SUDO` collapses to empty (reads the 0700 ollama tree); (b) `mount -o ro,loop,offset=` via `partx` instead of `losetup --partscan` (robust in-container); (c) fixed stale check #2 (`cli.js` → version-agnostic symlink-resolves test; CC 2.1+ ships bundled `bin/claude.exe`); (d) NEW check #9 asserts the deploy fix is wired so it can't silently regress. |

The old `vibeos-bootloader-fix.sh` is kept only as a reference sibling;
it is no longer in the install sequence. `vibeos-recover-bootloader`
remains as the manual escape hatch.

## Build + verify state

- Rebuilt via `scripts/build.sh` (~57 min, mirror-bound on apt). Output:
  `mkosi.output/vibeos.raw` (16.6 GiB, GPT: 512M ESP + ext4 root-x86-64).
- `scripts/verify-iso.sh`: **ALL 10 CHECKS PASS, exit 0, no password.**
  Confirmed in the built image: deploy script present + executable,
  `dontChroot: true`, kernel/ollama/claude(2.1.156)/calamares/vibbey all
  baked. `ExtraTrees=../calamares-config:/etc/calamares` is the sole
  config source (`mkosi.extra/etc/calamares` is empty), so the
  `dontChroot` edit takes effect.

## Confirm-it-worked smoke test (NEXT, on MSI)

1. Flash `vibeos.raw` to USB (see flash commands below / in chat).
2. Clean install on the MSI.
3. Reboot **WITHOUT the USB** → should land in Plasma directly, no
   recovery step.
4. Proof artifact: deploy writes `/vibeos-deploy-debug.log` to the LIVE
   USB ESP during install (pull USB, read it) + `/var/log/
   vibeos-bootctl-install.log` on the installed disk. Presence on the USB
   = the host-side script ran (the old chroot one never left a log).
5. If green → tag v2.0.0 final (drop -rc1), update iso.mwmai.no, archive
   this handoff. rc1 open-items #2 (ollama chown) + #3 (systemd-resolved)
   still open but non-blocking.

## Residual uncertainty

Cannot fully verify offline that Calamares exposes the target mounts in
the exact layout the deploy reuses; the script falls back to mounting by
partlabel if not. The only real test is the install on the MSI.

## Lesson

The single most useful diagnostic was the ABSENCE of the fix script's
own debug log on the USB ESP — it proved the script never ran where it
mattered, in one read, instead of guessing at the chroot internals.
"Produce/inspect a readable artifact first" held again.
