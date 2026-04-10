# VibeOS

**AI-native development environment for Linux. Free. Open source. Fun.**

![Vibbey — VibeOS Assistant](clippy/reference/concept.jpg)

*Vibbey, the VibeOS onboarding assistant, in the Neon Grid UI. Local Ollama, real 3D Clippy-lineage model, zero cloud round-trips.*

One command turns a fresh Ubuntu / Pop!\_OS install into a fully configured Claude Code workspace — with persistent memory, local AI models, and just the MCP servers you actually need.

```bash
curl -sSL https://raw.githubusercontent.com/Matswm86/vibeos/main/install.sh | bash
```

After that, **Vibbey** — your nostalgic local-AI guide — pops up as a floating desktop window and walks you through first-boot setup automatically. Vibbey runs 100% locally on Ollama (no API key needed), gets Claude Code authenticated, checks your MCP stack, and hands you off with the line:

> *"Looks like you're about to Vibe hard. Would you like to continue? ;)"*

Phase B shipped 2026-04-10 (v0.3.2+): Vibbey is a real webkit2gtk desktop window with a 3D Clippy-lineage model (via Three.js + GLTFLoader), chat-capable via a local Ollama proxy, with auto-detect of whichever model you have pulled (prefers `gemma3:4b`, falls back to `llama3.2:3b` etc.). Stage 4 — full OS rebrand + bootable ISO — is next.

---

## What gets installed

| Component | Version | Purpose |
|-----------|---------|---------|
| Python | 3.10+ (distro default) | MCP servers, Vibbey, tooling |
| Node.js | 22 LTS | Claude Code, npm MCPs |
| Docker | latest | Optional local services |
| Ollama | latest | Local AI models (Vibbey + your own) |
| Claude Code | latest | Primary AI assistant |
| GitHub CLI | latest | Repository operations |
| WebKit2 + GTK | system | Vibbey desktop window (falls back to system browser) |

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

## What VibeOS is (and will be)

**Today (v0.3.2)** — an installer + configuration layer on top of Ubuntu / Pop!\_OS. Everything downloads at install time, so you always get the latest Claude Code and latest MCPs. Vibbey runs as a webkit2gtk desktop window after the install finishes.

**Next (v0.4.0, Stage 4)** — a bootable `.iso` image with a full VibeOS rebrand: custom GRUB, Plymouth boot splash, GDM login theme, Neon Grid GTK theme (forked Yaru), custom icons, cursors, fonts (Orbitron / JetBrains Mono / VT323), Tron-grid wallpapers, and Vibbey auto-launching on first login. Flash with balenaEtcher, boot from USB, and you land in a running Claude Code session with Vibbey greeting you — zero terminal steps.

**Not bundling Claude Code.** It's proprietary Anthropic software. The installer downloads it directly from Anthropic, same as Chrome or VS Code installers.

---

## Meet Vibbey

Vibbey is VibeOS's onboarding character: nostalgic nod to Microsoft's old paperclip, self-aware, slightly cheeky, and actually useful this time. She runs on **local Ollama** (Gemma3 4B by default — no API key, no cloud round-trip, no model-training leak).

She lives in a **floating webkit2gtk desktop window** sized 420x560, always-on-top, with the VibeOS Neon Grid palette (magenta + cyan + violet, Tron-grid background). A real 3D paperclip model rendered via Three.js + GLTFLoader does a gentle idle bob while she chats. If webkit2gtk isn't available, she falls back to opening in your system browser.

Vibbey walks you through:

1. Hardware summary and recommendations
2. Experience-level detection (beginner / intermediate / advanced — adapts tone)
3. Claude Code authentication
4. MCP server configuration and verification
5. Full system check
6. Handoff to Claude Code with the signature *"Looks like you're about to Vibe hard"* line

`install.sh` auto-launches Vibbey the moment the install finishes. To run her again manually from any shell:

```bash
python3 -m clippy
```

(The `clippy` module contains Vibbey's launcher, server, Three.js scene, and voice. The directory name is a nod to the lineage — the character is Vibbey.)

To skip Vibbey (for CI, Docker tests, or scripted installs):

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
- [x] Stage 2: Vibbey — Ollama onboarding agent (guided first-boot experience)
- [x] Stage 2.5: Minimal MCP stack (filesystem removed in v0.3, auto-onboarding)
- [x] Stage 2.6: install.sh hardening (v0.3.1) — `/dev/tty` curl-pipe fallback, dual memory-location docs, `vibe` alias
- [x] **Stage 3: Vibbey Phase B** (v0.3.2) — real 3D Clippy-lineage model in a webkit2gtk desktop window, Three.js + GLTFLoader, local Ollama chat proxy, model auto-detect, python3 auto-reexec. "Clippy, but it actually works now."
- [ ] **Stage 4: VibeOS ISO + full OS rebrand** — bootable `.iso` with custom GRUB, Plymouth, GDM, Neon Grid GTK theme (forked Yaru), icons, cursors, fonts, wallpapers, and Vibbey auto-launching on first login. Ubuntu 22.04 LTS base, hosted at `iso.mwmai.no`. See the full plan in the companion workspace.

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

### Third-party assets

- **`clippy.glb`** — "Rigged Microsoft Clippy/Clippit" by [Freedumbanimates](https://sketchfab.com/Freedumbanimates) on Sketchfab, used under the [Sketchfab Standard](https://sketchfab.com/licenses) license. Textures were stripped for size; Vibbey animates the rig via Three.js root-transform. Full attribution in [`clippy/ATTRIBUTION.md`](clippy/ATTRIBUTION.md).
- **Concept image** (`clippy/reference/concept.jpg`) — visual direction reference for Phase 1 / Stage 4; Mats Mjåtvedt, 2026-04.
