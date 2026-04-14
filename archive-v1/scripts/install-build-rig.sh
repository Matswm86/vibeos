#!/usr/bin/env bash
# Install the VibeOS Stage 4 ISO build rig.
# Target host: any Ubuntu-family distro (tested on Pop!_OS 24.04, should
# work on Ubuntu 22.04/24.04 and Kubuntu).
#
# Installs: cubic (Custom Ubuntu ISO Creator), qemu + KVM, OVMF (UEFI firmware).
# Fetches: Kubuntu 22.04.5 LTS desktop amd64 ISO into ~/vibeos-build/base/
# Verifies: SHA256 against Canonical's published checksum.
#
# Run once before Phase A.
set -euo pipefail

say()  { printf '\e[35m[vibeos-rig]\e[0m %s\n' "$*"; }
ok()   { printf '\e[32m  ✓\e[0m %s\n' "$*"; }
warn() { printf '\e[33m  !\e[0m %s\n' "$*" >&2; }
die()  { printf '\e[31m  ✗\e[0m %s\n' "$*" >&2; exit 1; }

BUILD_DIR="$HOME/vibeos-build"
BASE_DIR="$BUILD_DIR/base"
ISO_NAME="kubuntu-22.04.5-desktop-amd64.iso"
ISO_URL="https://cdimage.ubuntu.com/kubuntu/releases/22.04/release/${ISO_NAME}"
SHA_URL="https://cdimage.ubuntu.com/kubuntu/releases/22.04/release/SHA256SUMS"

[ "$(id -u)" -eq 0 ] && die "do not run this as root — it will sudo where needed"
command -v sudo >/dev/null 2>&1 || die "sudo not installed"

# --- Step 1: cubic PPA + package ---
say "step 1 — install cubic"
if command -v cubic >/dev/null 2>&1; then
    ok "cubic already installed ($(cubic --version 2>/dev/null || echo version-unknown))"
else
    # Cubic maintains its own PPA
    sudo add-apt-repository -y ppa:cubic-wizard/release || warn "PPA add failed; cubic may fail to install"
    sudo apt-get update
    sudo apt-get install -y cubic
    ok "cubic installed"
fi

# --- Step 2: qemu + KVM + OVMF ---
say "step 2 — install qemu-kvm + OVMF"
PKGS="qemu-system-x86 qemu-kvm ovmf bridge-utils"
if dpkg -s qemu-system-x86 >/dev/null 2>&1; then
    ok "qemu-system-x86 already installed"
else
    sudo apt-get install -y $PKGS
    ok "qemu + ovmf installed"
fi

# Check KVM accessibility
if [ -e /dev/kvm ]; then
    if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        ok "/dev/kvm accessible to $(id -un)"
    else
        warn "/dev/kvm exists but not accessible — add your user to the kvm group:"
        warn "  sudo usermod -aG kvm $(id -un)  && logout/login"
    fi
else
    warn "/dev/kvm missing — virtualization may not be enabled in BIOS (VT-x / AMD-V)"
fi

# --- Step 3: build dirs ---
say "step 3 — prepare ~/vibeos-build/ tree"
mkdir -p "$BASE_DIR" "$BUILD_DIR/output" "$BUILD_DIR/work"
ok "build dirs ready at $BUILD_DIR"

# --- Step 4: fetch Kubuntu base ISO ---
say "step 4 — fetch Kubuntu 22.04.5 base ISO"
ISO_PATH="$BASE_DIR/$ISO_NAME"
if [ -f "$ISO_PATH" ]; then
    ok "base ISO already present ($(du -h "$ISO_PATH" | awk '{print $1}'))"
else
    say "downloading $ISO_URL (~4 GB, grab a coffee)"
    if command -v aria2c >/dev/null 2>&1; then
        aria2c -x 8 -s 8 -d "$BASE_DIR" -o "$ISO_NAME" "$ISO_URL"
    else
        curl -L --progress-bar -o "$ISO_PATH" "$ISO_URL"
    fi
    ok "ISO downloaded"
fi

# --- Step 5: verify SHA256 ---
say "step 5 — verify SHA256 against Canonical"
SHA_FILE="$BASE_DIR/SHA256SUMS"
curl -fsSL -o "$SHA_FILE" "$SHA_URL" || die "could not fetch $SHA_URL"
EXPECTED=$(grep "${ISO_NAME}\$" "$SHA_FILE" | awk '{print $1}' || true)
[ -n "$EXPECTED" ] || die "could not find $ISO_NAME in SHA256SUMS"
ACTUAL=$(sha256sum "$ISO_PATH" | awk '{print $1}')
if [ "$EXPECTED" = "$ACTUAL" ]; then
    ok "sha256 verified ($EXPECTED)"
else
    die "sha256 mismatch — expected $EXPECTED got $ACTUAL"
fi

# --- Step 6: report ---
printf '\n\e[36m=== build rig ready ===\e[0m\n'
printf '  cubic:       %s\n' "$(command -v cubic || echo MISSING)"
printf '  qemu x86_64: %s\n' "$(command -v qemu-system-x86_64 || echo MISSING)"
printf '  OVMF:        %s\n' "$([ -f /usr/share/OVMF/OVMF_CODE.fd ] && echo present || echo MISSING)"
printf '  KVM:         %s\n' "$([ -r /dev/kvm ] && echo accessible || echo INACCESSIBLE)"
printf '  base ISO:    %s\n' "$ISO_PATH"
printf '\nnext:\n'
printf '  1. cubic --newproject  # point at ~/vibeos-build/work/\n'
printf '  2. in the chroot shell, run scripts/chroot-inject.sh\n'
printf '  3. let cubic build the ISO into ~/vibeos-build/output/\n'
printf '  4. QEMU smoke test: qemu-system-x86_64 -enable-kvm -m 8G -bios OVMF_CODE.fd -cdrom vibeos-0.4.0.iso -boot d\n'
