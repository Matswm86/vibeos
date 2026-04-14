# Claude Code on VibeOS — Quickstart

Offline reference bundled with the ISO so Vibbey (and you) can answer the
common questions without a network round-trip.

## TL;DR
1. Click **Start Coding with Claude** on the desktop.
2. If prompted, paste your Anthropic API key. It goes to the keyring.
3. A Konsole window opens in `~/workspace/` with `claude` running.

## Where things live
| Thing | Path |
|---|---|
| Setup wizard | `/usr/bin/vibeos-claude-setup` |
| Launcher (shortcut target) | `/usr/bin/vibeos-claude-start` |
| Profile hook | `/etc/profile.d/vibeos-claude.sh` |
| Workspace | `~/workspace/` |
| Workspace settings | `~/workspace/.claude/settings.json` |
| Setup-complete flag | `~/.vibeos/claude-setup-complete` |
| Keyring label | `VibeOS — Anthropic Claude API key` |

## Rotating the API key
Run `vibeos-claude-setup` again. The wizard overwrites the keyring entry.

## Using the key from scripts
New login shells pick up `ANTHROPIC_API_KEY` from the keyring automatically
via `/etc/profile.d/vibeos-claude.sh`. If you need it in a non-login shell
or a systemd service:

```bash
export ANTHROPIC_API_KEY=$(secret-tool lookup schema org.vibeos.claude-code api-key default)
```

## Skipped setup — changed your mind?
Run `vibeos-claude-setup` any time. No uninstall needed.

## Claude Code itself
- Docs: https://docs.claude.com/claude-code (online)
- Package: `@anthropic-ai/claude-code` (installed globally via npm at ISO
  build time; upgrade with `sudo npm install -g @anthropic-ai/claude-code`)
- Version check: `claude --version`

## Troubleshooting
- **"claude: command not found"** — the CLI wasn't baked. Install:
  `sudo npm install -g @anthropic-ai/claude-code`
- **Keyring write fails** — KDE Wallet may not be running yet on first
  login. Retry after the desktop has fully loaded, or run:
  `systemctl --user start kwalletd5`
- **"Invalid API key"** — re-run `vibeos-claude-setup` and paste a fresh
  key from https://console.anthropic.com/account/keys
