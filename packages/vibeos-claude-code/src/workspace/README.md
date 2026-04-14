# ~/workspace — Your Claude Code home on VibeOS

This directory was scaffolded by `vibeos-claude-setup`. Claude Code treats it
as the default project root when launched via the "Start Coding with Claude"
shortcut.

## What's here
- `.claude/settings.json` — permissive dev-workstation defaults (read, write,
  edit, common tooling). Tighten these if the project needs it.

## Conventions
- One project per subdirectory: `~/workspace/my-project/`, not files at the
  workspace root.
- API key lives in the keyring, not in `.env`. To rotate it, re-run
  `vibeos-claude-setup`.

## Common commands
- `claude` — start an interactive Claude Code session.
- `claude --help` — CLI reference.
- `claude /help` — slash-command reference inside a session.

More docs: `/usr/share/vibeos/claude-code-docs/`.
