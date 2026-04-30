# VibeOS install pipeline fixes — handoff 2026-04-29

Multi-hour debugging session. Calamares + mkosi-built rootfs combo had
a pile of layered bugs that prevented a successful install. By end of
session, the live USB has been patched in-place to produce a working
install on next run.

## User's MSI state (as of session end)

| Disk | Role | State |
|---|---|---|
| `/dev/nvme0n1` (Kingston 2TB) | unused | empty |
| `/dev/nvme1n1` (Micron 512GB) | current install | boots, Plasma starts, **no window decorations** (kwin-x11 was missing). User can reinstall from the patched USB to get a working install. |

The user opted to reinstall from the patched USB rather than fix the
running install in place. **Next session: confirm the reinstall lands
a working desktop.**

## USB state (now)

The USB rootfs (`/dev/sdb2` when plugged into this workstation) has been
chrooted into and patched directly:

- `kwin-x11` + `kwin-wayland` installed from Ubuntu Noble main archive
  (the missing-kwin bug)
- `/usr/share/ollama` chowned to `ollama:ollama` (was `greeter:render`,
  which made the Ollama service redownload models from network)
- `/usr/local/bin/vibeos-recover-bootloader` — manual recovery script
- `/usr/local/sbin/vibeos-bootloader-fix.sh` — Calamares post-bootloader
  hook script
- All Calamares config fixes (see "What was fixed" below)

`/etc/apt/sources.list` was emptied again and `/etc/resolv.conf`
restored to the systemd-resolved symlink, so the live USB behaves
identically to a fresh build at runtime.

## What was fixed (in the order it bit us)

| File | Bug | Fix |
|---|---|---|
| `users.conf` | strict pwquality blocked any password | `allowWeakPasswords: true` + `minLength: -1` + `nonempty: false` + libpwquality minlen=1 |
| `unpackfs.conf` | `sourcefs: "auto"` invalid → "filesystem for / not supported" | `sourcefs: "file"` (rsync mode for live-IS-rootfs) |
| `partition.conf` | no `partitionLayout` → only EFI partition created, rsync wrote to live USB | added explicit root partition (100% of remaining space). The `type: 4f68bce3-…` line broke X11 on this Calamares version, do not re-add it. |
| `mount.conf` | `options: bind` (string) → `mount -o b,i,n,d` because Python iterated the string char-by-char | `options: [ bind ]` (list) for both `/dev` and `/run/udev` |
| `shellprocess.conf` (NEW) | unpackfs excluded `/tmp`, `/var/tmp` etc → kernel-install couldn't create staging tempdir | runs `mkdir -p /tmp /var/tmp /run /mnt /media /cdrom /home /target` post-rsync |
| `shellprocess_bootctl.conf` (NEW) | Calamares' built-in `bootctl install` is silent + fails when efivarfs not in chroot; kernel-install plugins also can't generate initrd because mkosi rootfs has no initramfs-tools | invokes `/usr/local/sbin/vibeos-bootloader-fix.sh` which copies live ESP `/vibeos/` tree to target ESP, runs `bootctl install --no-variables`, patches `root=UUID=` into loader entries, retypes target root partition GPT type to x86_64-root |
| `unpackfs/main.py` | `find / -type f` exits 1 on EACCES dirs (`/var/cache/private`, `/etc/credstore.encrypted`, `/root`) which Calamares treats as fatal | wrapped in `sh -c "find ... 2>/dev/null; true"`. Patched on USB; persisted via mkosi.postinst.chroot for future builds |
| Calamares YAML `script:` field | template substitution on `$VAR` flags every shell variable as missing Calamares variable | extract bash logic into a real script file, YAML just calls it by path |
| `mkosi.conf` Packages list | `kde-plasma-desktop` metapackage's `kwin-x11 \| kwin-wayland` is a Recommends; mkosi installs without recommends → no KWin binary | added `kwin-x11` explicitly |
| Live session UX | KDE screen lock + idle dim + auto-suspend → `Relogin=false` left users locked out | wrote `kscreenlockerrc`, `powermanagementprofilesrc`, set `Relogin=true` in autologin |
| `/etc/fstab` (live) | `/tmp` was on the rootfs partition; failed installer rsync filled the USB | `tmpfs /tmp tmpfs ... size=4G` |
| Plymouth splash | wordmark crop showed chat-window UI bleed; cream text on cream gradient invisible | new wordmark.png (480×320, Vibbey on solid ink-purple); show.qml redone with all-dark gradient + cream-on-purple text |

## What's still on the to-do list

1. **Rebuild ISO from updated `mkosi.conf`** — the source has all fixes baked in
   (kwin-x11, partitionLayout, mount.conf, etc.); a fresh ISO build (~30 min via
   `scripts/build.sh`) plus reflash gives plug-and-play. The current USB was
   patched in place but a fresh ISO is cleaner.
2. **Investigate why mkosi.postinst's `chown -R ollama:ollama /usr/share/ollama`
   doesn't survive into the final image** — files end up `greeter:render`. Likely
   the postinst chown ran with one UID assignment, but sddm-greeter being added
   later renumbered UIDs. Fix: either pin ollama's UID, or add a one-shot
   systemd service that re-chowns on first boot, or do the chown in
   `mkosi.finalize.chroot`.
3. **`systemd-resolved` not present as a service on the installed system** even
   though `mkosi.conf` lists `systemd-resolved` in Packages. Investigate — may
   be the package is named differently in Noble (it's split out of `systemd`
   as of 23.10). Confirm `systemd-resolved` is the right package name.
4. **(Optional) Replace Calamares `bootloader@vibeos` job entirely** with a
   single host-side `dontChroot: true` shellprocess that runs the deploy logic.
   Eliminates the entire kernel-install path so we never depend on initramfs-tools
   or `/etc/kernel/cmdline` again. Right now we run Calamares' bootloader job
   (which fails silently) AND the recovery script (which corrects it) — wasteful
   but works.
5. **`/etc/kernel/install.d/` shipping empty in installed system** even though
   `/usr/lib/kernel/install.d/` has the systemd-boot plugins. This is a Debian
   layout quirk; harmless given we override with our own deploy, but worth a
   cleanup if we ever go back to letting kernel-install do its thing.

## Files of record (source repo)

- `calamares-config/settings.conf` — instance + sequence with `shellprocess` and `shellprocess@bootctl`
- `calamares-config/modules/{users,unpackfs,partition,mount,shellprocess,shellprocess_bootctl,bootloader}.conf`
- `calamares-config/branding/vibeos/{show.qml,vibeos-welcome.svg}`
- `mkosi/mkosi.conf` — `kwin-x11` added to Packages
- `mkosi/mkosi.postinst.chroot` — patches `unpackfs/main.py` for EACCES tolerance
- `mkosi/mkosi.extra/usr/local/sbin/vibeos-bootloader-fix.sh` — runs at install time
- `mkosi/mkosi.extra/usr/local/bin/vibeos-recover-bootloader` — manual recovery
- `packages/vibeos-desktop/src/plymouth/vibeos-pacific-dawn/{wordmark.png,vibeos-pacific-dawn.script}`

## Next-session smoke test

1. Boot patched USB on MSI.
2. Run installer. Should complete without the prior bootloader/X11/kwin errors.
3. Reboot to NVMe. Plasma session should come up with titlebars, movable
   windows, Vibbey responding via local Ollama.
4. If yes → archive this handoff. Move on to the rebuild + flash + reinstall
   from a fresh ISO to validate the source-side fixes (without USB-patching).
5. If no → `/var/log/vibeos-bootctl-install.log` on the installed system has
   a complete script trace. Read that first, don't guess.

## Lesson worth keeping

This session was 12+ rounds of "USB here, fix, USB back". Most of it was me
chasing one symptom at a time instead of doing a full audit pass on every
config file involved. The single most useful diagnostic in the entire
session was the user's `vibeos-recover.log` — three lines of actual data
beat all the speculation. Going forward: **produce a readable artifact
first, look at it, then act**. Bias toward host-side scripts over chroot
voodoo when a working live system is available.
