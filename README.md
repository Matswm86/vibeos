# VibeOS

**AI-native development environment for Linux. Free. Open source. Fun.**

One command turns a fresh Pop!\_OS install into a fully configured Claude Code workspace — with persistent memory, local AI models, and just the MCP servers you actually need.

```bash
curl -sSL https://raw.githubusercontent.com/Matswm86/vibeos/main/install.sh | bash
```

After that, an Ollama-powered onboarding agent walks you through first-boot setup automatically. Coming soon: **Clippy** — your nostalgic local-AI guide, because VibeOS should be a little bit fun.

---

## What gets installed

| Component | Version | Purpose |
|-----------|---------|---------|
| Python | 3.11 | MCP servers, tooling |
| Node.js | 22 LTS | Claude Code, npm MCPs |
| Docker | latest | Optional local services |
| Ollama | latest | Local AI models |
| Claude Code | latest | Primary AI assistant |
| GitHub CLI | latest | Repository operations |

**Default MCP stack** — minimal by design, zero infrastructure required:

| MCP Server | Backend | Purpose |
|-----------|---------|---------|
| `memory` | SQLite | Persistent knowledge graph at `~/.claude-memory` |
| `github` | API | Repository operations (needs `GITHUB_TOKEN`) |

> **Note**: `filesystem` MCP was removed in v0.3 — Claude Code's native `Read` / `Write` / `Edit` / `Glob` / `Grep` tools cover the same ground without the tool-name duplication. Add it back manually if you prefer the MCP flow.

---

## Hardware requirements

**Minimum** (VibeOS installs and runs fully):
- CPU: 64-bit x86, 2018 or later, AVX2 support
- RAM: 8 GB
- Storage: 20 GB free
- GPU: not required
- Internet: required for Claude Code API

**Recommended** (comfortable daily use):
- RAM: 16 GB
- GPU: any discrete NVIDIA or AMD (for faster local models)
- Storage: 60 GB free

The onboarding model (Gemma3 4B) runs on CPU-only. Claude Code itself requires no local GPU — it runs on Anthropic's API.

---

## What VibeOS is not

- Not a Linux distro. It's an installer + configuration layer on top of Pop!\_OS (or any Ubuntu-based system).
- Not a static image. Everything downloads at install time — you always get the latest Claude Code, latest MCPs.
- Not bundling Claude Code. It's proprietary Anthropic software. The installer downloads it directly from Anthropic, same as Chrome or VS Code installers.

---

## Onboarding agent

After installation, VibeOS **automatically** launches a guided onboarding experience powered by Ollama (runs locally, no API key needed). It walks you through:

1. Hardware summary and recommendations
2. Experience-level detection (adapts tone)
3. Claude Code authentication
4. MCP server configuration and verification
5. Full system check
6. Handoff to Claude Code

No prompts, no choices — just run `install.sh` and follow along. To run it again manually:

```bash
cd ~/.vibeos && python3 -m onboarding
```

To skip onboarding (for CI, Docker tests, or scripted installs):

```bash
VIBEOS_NO_ONBOARDING=1 ./install.sh
```

## After install

```bash
# Authenticate Claude Code
claude

# Authenticate GitHub
gh auth login

# Set GitHub token for MCP server
export GITHUB_TOKEN=ghp_...    # add to ~/.bashrc

# Start Claude Code in your project
cd ~/my-project
claude
```

Your `~/CLAUDE.md` tells Claude about your workspace. Edit it to describe your project and preferences.

---

## Power user tier (opt-in)

Add hosted vector + graph memory for cross-session persistence and semantic search:

```bash
# Optional: start local Qdrant + Neo4j via Docker
# (install.sh sets up Docker but doesn't start these by default)
docker run -p 6333:6333 qdrant/qdrant
```

Or use [VibeOS Managed MCP](https://github.com/Matswm86/vibeos) — hosted Qdrant, Neo4j, and mem0 endpoints you drop into your `settings.json`. No infrastructure to run.

---

## Roadmap

- [x] Stage 1: Generic installer
- [x] Stage 2: Ollama onboarding agent (guided first-boot experience)
- [x] Stage 2.5: Minimal MCP stack (filesystem removed in v0.3, auto-onboarding)
- [ ] **Stage 3: Clippy** — nostalgic 3D assistant character (real GLB model + Three.js + local Ollama). Pops up automatically after install, guides users through first boot, answers questions. "Clippy, but it actually works now." See [`plans/vibeos-clippy.md`](../../plans/vibeos-clippy.md).
- [ ] Stage 4: Live USB / custom ISO (Pop!_OS + VibeOS + Clippy pre-baked, auto-launches on boot)

---

## Contributing

Issues and PRs welcome. The installer targets Ubuntu 22.04+ / Pop!\_OS 22.04+.

To test locally:
```bash
git clone https://github.com/Matswm86/vibeos
cd vibeos
chmod +x install.sh
./install.sh
```

---

## License

MIT — see [LICENSE](LICENSE).
