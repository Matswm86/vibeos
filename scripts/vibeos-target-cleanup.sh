#!/bin/bash
# /usr/local/sbin/vibeos-target-cleanup.sh
#
# Strip every live-session artifact from the INSTALLED system. Invoked by
# Calamares CHROOTED into the target (shellprocess, dontChroot: false), so
# every path below is a target path — the live USB is never touched.
#
# Two stages, wired in calamares-config/settings.conf:
#   (no args)  full strip — runs right after unpackfs, BEFORE the users
#              module, so the freshly created account may even be named
#              "vibeos" without colliding with the live user.
#   --verify   assert-only — runs at the END of the exec sequence. Exits
#              non-zero if any live artifact survived, which makes
#              Calamares fail the install VISIBLY instead of shipping a
#              system that boots back into the live "install page".
#
# History: this replaces calamares-config/modules/contextualprocess.conf,
# which was written in shellprocess syntax (install_clean:/sequence:) that
# the contextualprocess module silently ignores — the cleanup NEVER ran,
# so every installed system was a byte-for-byte clone of the live session:
# autologin as the live user, live-session marker present, Vibbey install
# sidebar + Calamares autostart firing, NOPASSWD sudo. That is the
# "rebooted into the install page again" bug.
#
# Log: /var/log/vibeos-target-cleanup.log (on the installed system).

set -uo pipefail

LOG=/var/log/vibeos-target-cleanup.log
mkdir -p /var/log

log() {
    printf '[target-cleanup] %s\n' "$*"
    printf '[target-cleanup] %s\n' "$*" >> "$LOG" 2>/dev/null
    return 0
}

# Every live-session file that must NOT exist on an installed system.
LIVE_ARTIFACTS=(
    /etc/vibeos/live-session
    /etc/xdg/autostart/vibeos-live-installer.desktop
    /usr/share/applications/install-vibeos.desktop
    /usr/share/applications/calamares.desktop
    /etc/sudoers.d/99-vibeos-live
    /etc/sddm.conf.d/autologin.conf
)

verify() {
    local bad=0
    for f in "${LIVE_ARTIFACTS[@]}"; do
        if [ -e "$f" ]; then
            log "FAIL: live artifact still present: $f"
            bad=1
        fi
    done
    # NOTE: no passwd check for 'vibeos' here — the strip stage (which
    # runs BEFORE the users module) already hard-fails if userdel cannot
    # remove the live user. If a 'vibeos' account exists at verify time it
    # was created by the users module at the new owner's request.
    if [ "$bad" -ne 0 ]; then
        log "VERIFY FAILED — installed system would boot into the live install page"
        exit 1
    fi
    log "verify OK: no live-session artifacts on target"
    return 0
}

log "=== $(date -Is) starting (mode: ${1:-strip}) ==="

if [ "${1:-}" = "--verify" ]; then
    verify
    log "=== done OK (verify) ==="
    exit 0
fi

# ── 1. Remove the live user copied in by unpackfs ──────────────────────
# Runs pre-users-module: the target has no processes and no utmp, so
# userdel is safe. -f also tolerates the "user not fully set up" state.
if getent passwd vibeos >/dev/null 2>&1; then
    if userdel -f -r vibeos 2>>"$LOG"; then
        log "removed live user 'vibeos' (+ home)"
    else
        # userdel -r warns (rc!=0) if the home dir is already gone; the
        # passwd entry removal is what matters. Re-check before failing.
        if getent passwd vibeos >/dev/null 2>&1; then
            log "FATAL: userdel could not remove live user 'vibeos'"
            exit 1
        fi
        log "removed live user 'vibeos' (userdel warned, passwd entry gone)"
    fi
fi
rm -rf /home/vibeos
getent group vibeos >/dev/null 2>&1 && groupdel vibeos 2>>"$LOG" || true

# ── 2. Remove live-only files ──────────────────────────────────────────
for f in "${LIVE_ARTIFACTS[@]}"; do
    if [ -e "$f" ]; then
        rm -f "$f" && log "removed $f"
    fi
done

# ── 3. Assert immediately — fail the install loudly, not silently ─────
verify

log "=== $(date -Is) done OK (strip) ==="
exit 0
