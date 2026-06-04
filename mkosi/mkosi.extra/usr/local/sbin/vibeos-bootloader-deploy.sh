#!/bin/bash
# /usr/local/sbin/vibeos-bootloader-deploy.sh
#
# HOST-SIDE bootloader deploy. Invoked by Calamares' shellprocess@bootctl
# step with `dontChroot: true`, so it runs in the LIVE session's normal
# mount namespace -- exactly like the proven `vibeos-recover-bootloader`.
# This is the fix for the v2.0.0-rc1 black-screen-on-first-boot bug:
#
#   The old `vibeos-bootloader-fix.sh` ran INSIDE the Calamares chroot,
#   where the live USB ESP is already mounted (busy / read-only) in the
#   host namespace. Its `mount -o rw` of the live ESP failed, so the
#   `/vibeos/` kernel tree + loader entries were NEVER copied to the
#   target ESP (that copy is gated on finding the live ESP). The target
#   booted systemd-boot with no kernel entry -> black screen. The absence
#   of the script's own debug log on the live ESP after an install was
#   the tell that it never reached the live ESP at all.
#
# Running host-side removes the chroot mount restriction entirely. We do
# NOT assume `/` is the target (it is the live USB here); we locate the
# freshly-installed target by partlabel `vibeos-root` and reuse whatever
# mountpoints Calamares already established.
#
#   Logs: /var/log/vibeos-bootctl-install.log on the TARGET, and
#         /vibeos-deploy-debug.log on the LIVE ESP (pull-off-USB readable).

set -uo pipefail

LIVE_LOG=""
TARGET_LOG=""          # set once target rootfs mountpoint is known
SELF_MOUNTS=()         # mountpoints WE created, to clean up; never touch Calamares' own

log() {
    printf '[bootloader-deploy] %s\n' "$*"
    [ -n "$TARGET_LOG" ] && printf '[bootloader-deploy] %s\n' "$*" >> "$TARGET_LOG" 2>/dev/null
    [ -n "$LIVE_LOG" ]   && printf '[bootloader-deploy] %s\n' "$*" >> "$LIVE_LOG"   2>/dev/null
    return 0
}

fail() { log "FATAL: $*"; cleanup; exit 1; }

cleanup() {
    sync
    # Unmount only what we mounted, in reverse order. Never unmount
    # Calamares' own target mounts (it umounts those in its umount job).
    for ((i=${#SELF_MOUNTS[@]}-1; i>=0; i--)); do
        umount "${SELF_MOUNTS[i]}" 2>/dev/null || true
    done
}
trap cleanup EXIT

log "=== $(date -Is) starting (host-side, $(uname -r)) ==="

# -- 1. Live ESP: the disk we booted from -------------------------------
LIVE_ROOT_DEV="$(findmnt -no SOURCE / 2>/dev/null || true)"
[ -n "$LIVE_ROOT_DEV" ] || fail "cannot determine live root device"
LIVE_DISK="$(echo "$LIVE_ROOT_DEV" | sed -E 's|p?[0-9]+$||')"
log "live root=$LIVE_ROOT_DEV  live disk=$LIVE_DISK"

LIVE_ESP_DEV=""
for p in $(lsblk -lnpo NAME "$LIVE_DISK" | tail -n +2); do
    [ "$(blkid -s TYPE -o value "$p" 2>/dev/null)" = "vfat" ] && { LIVE_ESP_DEV="$p"; break; }
done
[ -n "$LIVE_ESP_DEV" ] || fail "no vfat ESP on live disk $LIVE_DISK"
log "live ESP dev=$LIVE_ESP_DEV"

# Reuse existing mount (gpt-auto-generator usually has it at /boot); else ro-mount.
LIVE_ESP="$(findmnt -no TARGET "$LIVE_ESP_DEV" 2>/dev/null | head -1 || true)"
if [ -z "$LIVE_ESP" ]; then
    LIVE_ESP=/run/vibeos-live-esp
    mkdir -p "$LIVE_ESP"
    mount -o ro "$LIVE_ESP_DEV" "$LIVE_ESP" || fail "cannot mount live ESP $LIVE_ESP_DEV"
    SELF_MOUNTS+=("$LIVE_ESP")
fi
[ -d "$LIVE_ESP/vibeos" ] || fail "live ESP at $LIVE_ESP has no /vibeos tree"
LIVE_LOG="$LIVE_ESP/vibeos-deploy-debug.log"
# only writable if the live ESP mount is rw; harmless if it silently no-ops
: > "$LIVE_LOG" 2>/dev/null || LIVE_LOG=""
log "live ESP mounted at $LIVE_ESP (debug log: ${LIVE_LOG:-<ro, target only>})"

# -- 2. Target root: partlabel vibeos-root, NOT the live USB ------------
CANDS="$(blkid -t PARTLABEL=vibeos-root -o device 2>/dev/null | grep -vx "$LIVE_ROOT_DEV" || true)"
[ -n "$CANDS" ] || fail "no installed vibeos-root partition found (other than live USB)"

TARGET_ROOT_DEV=""; NEWEST=0
for p in $CANDS; do
    mp="$(findmnt -no TARGET "$p" 2>/dev/null | head -1 || true)"
    own=""
    if [ -z "$mp" ]; then
        mp=/run/vibeos-scan; mkdir -p "$mp"
        mount -o ro "$p" "$mp" 2>/dev/null || continue
        own=1
    fi
    mt="$(stat -c %Y "$mp/etc/fstab" 2>/dev/null || echo 0)"
    [ "$mt" -gt "$NEWEST" ] && { NEWEST=$mt; TARGET_ROOT_DEV="$p"; }
    [ -n "$own" ] && umount "$mp" 2>/dev/null || true
done
[ -n "$TARGET_ROOT_DEV" ] || fail "none of the vibeos-root candidates were mountable"
TARGET_DISK="$(echo "$TARGET_ROOT_DEV" | sed -E 's|p?[0-9]+$||')"
TARGET_PARTNUM="$(echo "$TARGET_ROOT_DEV" | grep -oE '[0-9]+$')"
log "target root=$TARGET_ROOT_DEV  disk=$TARGET_DISK  partnum=$TARGET_PARTNUM"

# Reuse Calamares' target-root mount; else mount it ourselves rw.
TARGET_ROOT="$(findmnt -no TARGET "$TARGET_ROOT_DEV" 2>/dev/null | head -1 || true)"
if [ -z "$TARGET_ROOT" ]; then
    TARGET_ROOT=/run/vibeos-target
    mkdir -p "$TARGET_ROOT"
    mount -o rw "$TARGET_ROOT_DEV" "$TARGET_ROOT" || fail "cannot mount target root"
    SELF_MOUNTS+=("$TARGET_ROOT")
fi
mkdir -p "$TARGET_ROOT/var/log"
TARGET_LOG="$TARGET_ROOT/var/log/vibeos-bootctl-install.log"
log "target rootfs at $TARGET_ROOT"

# -- 3. Target ESP: vfat on the target disk -----------------------------
TARGET_ESP_DEV="$(lsblk -lnpo NAME,FSTYPE "$TARGET_DISK" | awk '$2=="vfat"{print $1; exit}')"
[ -n "$TARGET_ESP_DEV" ] || fail "target disk $TARGET_DISK has no vfat ESP"

# Prefer Calamares' mount (usually $TARGET_ROOT/boot/efi); else mount it.
TARGET_ESP="$(findmnt -no TARGET "$TARGET_ESP_DEV" 2>/dev/null | head -1 || true)"
if [ -z "$TARGET_ESP" ]; then
    TARGET_ESP="$TARGET_ROOT/boot/efi"
    mkdir -p "$TARGET_ESP"
    mount -o rw "$TARGET_ESP_DEV" "$TARGET_ESP" || fail "cannot mount target ESP"
    SELF_MOUNTS+=("$TARGET_ESP")
fi
log "target ESP dev=$TARGET_ESP_DEV mounted at $TARGET_ESP"

# -- 4. Copy /vibeos/ kernel tree + loader entries (THE step that was skipped) --
rm -rf "$TARGET_ESP/vibeos"
cp -aR "$LIVE_ESP/vibeos" "$TARGET_ESP/" || fail "failed to copy /vibeos tree"
mkdir -p "$TARGET_ESP/loader/entries"
cp -f "$LIVE_ESP"/loader/entries/*.conf "$TARGET_ESP/loader/entries/" 2>/dev/null || true
log "copied /vibeos tree + loader entries to target ESP"

# -- 5. root=UUID=: fstab first, blkid fallback (closes old step-D FATAL) --
ROOT_UUID="$(awk '$2=="/" && $3=="ext4"{print $1; exit}' "$TARGET_ROOT/etc/fstab" 2>/dev/null | sed 's|^UUID=||')"
if [ -z "$ROOT_UUID" ]; then
    log "target fstab had no ext4 / line; deriving root UUID from blkid of $TARGET_ROOT_DEV"
    ROOT_UUID="$(blkid -s UUID -o value "$TARGET_ROOT_DEV" 2>/dev/null || true)"
fi
[ -n "$ROOT_UUID" ] || fail "could not determine target root UUID"
log "target root UUID=$ROOT_UUID"

CMDLINE="root=UUID=$ROOT_UUID rw quiet splash loglevel=3 systemd.show_status=auto"
mkdir -p "$TARGET_ROOT/etc/kernel"
echo "$CMDLINE" > "$TARGET_ROOT/etc/kernel/cmdline"

shopt -s nullglob
for f in "$TARGET_ESP"/loader/entries/*.conf; do
    if grep -q '^options' "$f"; then
        grep -q 'root=' "$f" || sed -i "s|^options[[:space:]]*|options root=UUID=$ROOT_UUID rw |" "$f"
    else
        echo "options $CMDLINE" >> "$f"
    fi
    log "loader entry now: $(grep '^options' "$f")"
done
shopt -u nullglob

# -- 6. systemd-boot install + firmware fallback ------------------------
bootctl --esp-path="$TARGET_ESP" --no-variables install 2>&1 | tee -a "$TARGET_LOG" \
    || bootctl --esp-path="$TARGET_ESP" install 2>&1 | tee -a "$TARGET_LOG" \
    || log "WARN: bootctl install non-zero (ok if EFI files are present)"
mkdir -p "$TARGET_ESP/EFI/BOOT" "$TARGET_ESP/EFI/systemd"
cp -f /usr/lib/systemd/boot/efi/systemd-bootx64.efi "$TARGET_ESP/EFI/systemd/systemd-bootx64.efi"
cp -f /usr/lib/systemd/boot/efi/systemd-bootx64.efi "$TARGET_ESP/EFI/BOOT/BOOTX64.EFI"
printf 'timeout 3\nconsole-mode max\n' > "$TARGET_ESP/loader/loader.conf"
log "systemd-boot installed; BOOTX64.EFI fallback written"

# -- 7. Retype root partition to x86_64-root GPT type (auto-discovery pathway) --
if command -v sgdisk >/dev/null 2>&1; then
    sgdisk -t "$TARGET_PARTNUM:4f68bce3-e8cd-4db1-96e7-fbcaf984b709" "$TARGET_DISK" 2>&1 \
        | tee -a "$TARGET_LOG" \
        && log "retyped $TARGET_ROOT_DEV to x86_64-root GPT type" \
        || log "WARN: sgdisk retype failed (root=UUID= still covers boot)"
else
    log "WARN: sgdisk not present; relying on root=UUID= only"
fi

# -- 8. Audit dump ------------------------------------------------------
{
    echo "=== target ESP layout ==="; ls -laR "$TARGET_ESP"
    echo "=== loader entries ==="; cat "$TARGET_ESP"/loader/entries/*.conf 2>/dev/null
    echo "=== /etc/kernel/cmdline ==="; cat "$TARGET_ROOT/etc/kernel/cmdline" 2>/dev/null
    echo "=== blkid ==="; blkid
} >> "$TARGET_LOG" 2>&1
[ -n "$LIVE_LOG" ] && cat "$TARGET_LOG" >> "$LIVE_LOG" 2>/dev/null

log "=== $(date -Is) done OK ==="
exit 0
