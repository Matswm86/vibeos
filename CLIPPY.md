---
name: VibeOS Vibbey Assistant
description: Hybrid Groq + Ollama "Vibbey" character for VibeOS — nostalgic Clippy-lineage UI assistant with contextual workspace suggestions and safe-command tool use
type: project
---

**What Vibbey is**: a nostalgic 3D onboarding + day-to-day assistant character for VibeOS. Clippy-lineage lineage (literally — the base `clippy.glb` mesh is a rigged Sketchfab Clippy model), but actually useful this time, and running on a modern LLM backend instead of 1997 heuristics.

**Concept**:
- Lives in the VibeOS UI as a 3D character in a webkit2gtk desktop window anchored to the bottom-right of the screen
- Walks first-time users through install + configuration on boot
- Answers day-to-day questions about the VibeOS stack, Claude Code, git, Ollama, Docker, Python, etc.
- Can run ~15 allowlisted read-only shell commands on the user's behalf with per-command confirmation (`claude --version`, `gh auth status`, `ollama list`, `docker info`, etc.)
- Friendly, slightly cheeky personality — "It looks like you're deploying an MCP server. Want me to check your config?"
- Good branding angle: "Clippy, but it actually works now — and this time it's Vibbey"

**Brain (3-tier router)**:
1. **BYO Groq key** at `~/.vibeos/groq.key` → unlimited smart mode on `llama-3.3-70b-versatile` (~500 tok/s)
2. **VibeOS bootstrap proxy** at `groq.mwmai.no` → 300 free messages so first-time users get smart mode without signing up for anything
3. **Local Ollama** fallback (`gemma3:4b` default, auto-detects whatever the user has pulled) → private, offline, no cost

Tier selection is automatic: use the highest-available tier, fall through on error or quota exhaustion. The router lives at `clippy/groq_proxy.py`.

**Why:** Differentiator for VibeOS. Adds personality to developer tooling. Nostalgia hook for social media virality. The hybrid brain means newbies get smart-mode answers out of the box (via the bootstrap proxy) but power users can BYO key or go fully offline.

**Related files**:
- `clippy/static/main.js` — Three.js scene, GLTFLoader, idle animation
- `clippy/server.py` — HTTP server that glues the frontend to the LLM router
- `clippy/groq_proxy.py` — 3-tier router
- `clippy/tools.py` — 15-command allowlist
- `clippy/knowledge/` — static knowledge pack injected into Vibbey's system prompt
- `clippy/dialogue.py` — Vibbey's voice + canned lines
