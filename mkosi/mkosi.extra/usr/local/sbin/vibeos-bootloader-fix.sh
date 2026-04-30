#!/bin/bash
# /usr/local/sbin/vibeos-bootloader-fix.sh
#
# Runs in the target chroot from Calamares' shellprocess@bootctl step
# AFTER the (broken) bootloader job. Replaces what Calamares produced
# with a known-good copy of the live USB's ESP layout.
#
# Logs go to /var/log/vibeos-bootctl-install.log on the *target*, AND
# (if we can find + mount the live ESP read-write) to
# /vibeos-fix-debug.log on the *live USB ESP* itself so we can pull
# the file off the USB and read it back without needing to boot the
# installed system.

set -uo pipefail
TARGET_LOG=/var/log/vibeos-bootctl-install.log
mkdir -p /var/log

LIVE_LOG_PATH=""

log() {
    printf '[bootloader-fix] %s\n' "$*" | tee -a "$TARGET_LOG"
    [ -n "$LIVE_LOG_PATH" ] && [ -d "$(dirname "$LIVE_LOG_PATH")" ] && \
        printf '[bootloader-fix] %s\n' "$*" >> "$LIVE_LOG_PATH"
}

log "=== $(date -Is) starting ==="
log "kernel: $(uname -a)"
log "/dev contents (relevant):"
ls -la /dev/sd* /dev/nvme* /dev/disk/by-label 2>&1 | tee -a "$TARGET_LOG" | head -40

# ─── A. Find + mount the live USB ESP (read-write so we can log to it) ───
mkdir -p /mnt/live-esp
LIVE_ESP=""

# Try every plausible source. Refuse the *target* ESP (already mounted at
# /boot/efi so its UUID is the one in /etc/fstab for /boot/efi).
TARGET_ESP_UUID="$(awk '$2=="/boot/efi" {print $1; exit}' /etc/fstab | sed 's|^UUID=||' | tr 'a-f' 'A-F')"
log "target ESP UUID (will be skipped): $TARGET_ESP_UUID"

candidates="$(ls /dev/sd?1 /dev/nvme?n?p1 /dev/mmcblk?p1 2>/dev/null) \
            $(ls /dev/disk/by-label/* 2>/dev/null)"
log "candidate ESPs:"
echo "$candidates" | tr ' ' '\n' | tee -a "$TARGET_LOG"

for src in $candidates; do
    [ -e "$src" ] || continue
    # Skip the target ESP (its FSUUID matches what /etc/fstab says for /boot/efi)
    src_uuid="$(blkid -s UUID -o value "$src" 2>/dev/null | tr 'a-f' 'A-F')"
    if [ -n "$TARGET_ESP_UUID" ] && [ "$src_uuid" = "$TARGET_ESP_UUID" ]; then
        log "skipping target ESP: $src ($src_uuid)"
        continue
    fi
    if mount -t vfat -o rw "$src" /mnt/live-esp 2>/dev/null \
       || mount -o rw "$src" /mnt/live-esp 2>/dev/null; then
        if [ -d /mnt/live-esp/vibeos ]; then
            LIVE_ESP="$src"
            LIVE_LOG_PATH=/mnt/live-esp/vibeos-fix-debug.log
            : > "$LIVE_LOG_PATH"
            log "found live ESP at $src — writing debug log to $LIVE_LOG_PATH"
            break
        fi
        umount /mnt/live-esp 2>/dev/null || true
    fi
done

if [ -z "$LIVE_ESP" ]; then
    log "FATAL: could not locate live ESP — listing every block device for diagnosis"
    blkid 2>&1 | tee -a "$TARGET_LOG"
    lsblk -o NAME,FSTYPE,LABEL,UUID,SIZE,MOUNTPOINT 2>&1 | tee -a "$TARGET_LOG"
fi

# ─── B. Copy /vibeos/ tree + loader entries from live ESP to target ESP ─
if [ -n "$LIVE_ESP" ]; then
    log "ESP contents (live): $(ls /mnt/live-esp 2>&1)"
    log "ESP contents (target before copy): $(ls /boot/efi 2>&1)"
    rm -rf /boot/efi/vibeos
    cp -aR /mnt/live-esp/vibeos /boot/efi/ && log "copied /vibeos/ tree"
    if ls /mnt/live-esp/loader/entries/*.conf >/dev/null 2>&1; then
        mkdir -p /boot/efi/loader/entries
        cp -f /mnt/live-esp/loader/entries/*.conf /boot/efi/loader/entries/ && \
            log "copied loader entries"
    fi
fi

# ─── C. systemd-bootx64.efi belt-and-braces ─────────────────────────────
mkdir -p /boot/efi/EFI/BOOT /boot/efi/EFI/systemd
bootctl --esp-path=/boot/efi --no-variables install 2>&1 | tee -a "$TARGET_LOG" || \
bootctl --esp-path=/boot/efi install 2>&1 | tee -a "$TARGET_LOG" || \
log "WARN: bootctl install returned non-zero"
cp -f /usr/lib/systemd/boot/efi/systemd-bootx64.efi /boot/efi/EFI/systemd/systemd-bootx64.efi
cp -f /usr/lib/systemd/boot/efi/systemd-bootx64.efi /boot/efi/EFI/BOOT/BOOTX64.EFI
log "systemd-bootx64.efi placed in /EFI/systemd and /EFI/BOOT/BOOTX64.EFI"

# ─── D. root=UUID= cmdline ──────────────────────────────────────────────
ROOT_UUID="$(awk '$2=="/" && $3=="ext4" {print $1; exit}' /etc/fstab | sed 's|^UUID=||')"
if [ -n "$ROOT_UUID" ]; then
    log "ROOT_UUID=$ROOT_UUID"
    CMDLINE="root=UUID=$ROOT_UUID rw quiet splash loglevel=3 systemd.show_status=auto"
    echo "$CMDLINE" > /etc/kernel/cmdline
    for f in /boot/efi/loader/entries/*.conf; do
        [ -f "$f" ] || continue
        log "patching entry: $f"
        if grep -q '^options' "$f"; then
            if ! grep -q 'root=' "$f"; then
                sed -i "s|^options[[:space:]]*|options root=UUID=$ROOT_UUID rw |" "$f"
                log "  added root=UUID="
            else
                log "  already had root="
            fi
        else
            echo "options $CMDLINE" >> "$f"
            log "  appended options line"
        fi
    done
else
    log "FATAL: no ext4 / line in /etc/fstab"
    cat /etc/fstab | tee -a "$TARGET_LOG"
fi

# ─── E. Retype root partition to x86_64-root GPT type ───────────────────
if command -v sgdisk >/dev/null 2>&1; then
    ROOT_DEV="$(findmnt -no SOURCE / 2>/dev/null || true)"
    log "ROOT_DEV=$ROOT_DEV"
    if [ -n "$ROOT_DEV" ]; then
        DISK="$(echo "$ROOT_DEV" | sed -E 's|p?[0-9]+$||')"
        PARTNUM="$(echo "$ROOT_DEV" | grep -oE '[0-9]+$')"
        log "retyping $DISK partition $PARTNUM to x86_64-root GPT type"
        sgdisk -t "$PARTNUM:4f68bce3-e8cd-4db1-96e7-fbcaf984b709" "$DISK" 2>&1 | tee -a "$TARGET_LOG" || \
            log "WARN: sgdisk could not retype $ROOT_DEV"
    fi
else
    log "WARN: sgdisk not installed"
fi

# ─── F. loader.conf ─────────────────────────────────────────────────────
printf 'timeout 3\nconsole-mode max\n' > /boot/efi/loader/loader.conf
log "wrote loader.conf"

# ─── G. Final audit dump ────────────────────────────────────────────────
{
    echo
    echo "=== ESP layout (/boot/efi) ==="
    ls -laR /boot/efi/
    echo
    echo "=== loader entries ==="
    cat /boot/efi/loader/entries/*.conf 2>/dev/null
    echo
    echo "=== /etc/kernel/cmdline ==="
    cat /etc/kernel/cmdline 2>/dev/null
    echo
    echo "=== /etc/fstab ==="
    cat /etc/fstab
    echo
    echo "=== blkid ==="
    blkid
} | tee -a "$TARGET_LOG" | { [ -n "$LIVE_LOG_PATH" ] && tee -a "$LIVE_LOG_PATH" || cat > /dev/null; }

# Make sure live ESP log is flushed before umount
if [ -n "$LIVE_ESP" ]; then
    sync
    umount /mnt/live-esp 2>/dev/null || true
fi

log "=== $(date -Is) done ==="
exit 0
