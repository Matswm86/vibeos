# Claude Code — Workspace Configuration

## About this workspace

> Edit this file to describe your project. Claude reads it at the start of every session.

**Project**: [Your project name here]
**Description**: [What you're building]
**Stack**: [e.g. Python / FastAPI / PostgreSQL]

## Rules

1. All code uses absolute paths via `Path` (never hardcoded strings).
2. Python: f-strings for formatting, `Pathlib` for file operations, specific exceptions only.
3. No hardcoded credentials — use environment variables or `.env` files.
4. Never commit secrets. Check `.gitignore` before `git add`.

## MCP Servers

| Server | Purpose |
|--------|---------|
| memory | Persistent knowledge graph (SQLite) |
| github | Repository operations |

## Project layout

```
~/
├── CLAUDE.md          ← this file
├── .mcp.json          ← MCP server config
└── [your projects]/
```

## User preferences

- [Add your preferences here — language, frameworks, style]
