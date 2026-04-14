# /etc/profile.d/vibeos-claude.sh
#
# Export ANTHROPIC_API_KEY from the desktop keyring into every login shell.
# Safe: no-op if the key is not set, or if secret-tool is unavailable, or if
# the user has already set ANTHROPIC_API_KEY themselves. Never fails login.
#
# Installed by vibeos-claude-code.deb.

if [ -z "${ANTHROPIC_API_KEY:-}" ] && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    if command -v secret-tool >/dev/null 2>&1; then
        _vibeos_claude_key=$(secret-tool lookup \
            schema org.vibeos.claude-code \
            api-key default 2>/dev/null || true)
        if [ -n "$_vibeos_claude_key" ]; then
            ANTHROPIC_API_KEY="$_vibeos_claude_key"
            export ANTHROPIC_API_KEY
        fi
        unset _vibeos_claude_key
    fi
fi
