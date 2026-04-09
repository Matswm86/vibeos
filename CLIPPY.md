---
name: VibeOS Vibbey Assistant
description: Ollama-powered "Vibbey" character for VibeOS — nostalgic Clippy-lineage UI assistant with contextual MCP workspace suggestions
type: project
---

**Idea**: Add an Ollama-powered assistant character to VibeOS — **Vibbey**, a nostalgic nod to Microsoft's old paperclip, but actually useful this time.

**Concept**:
- Lives in the VibeOS UI as a small animated character
- Pops up with contextual suggestions based on what user is doing in their managed MCP workspace
- Powered by local Ollama model (lightweight, privacy-first)
- Friendly, slightly cheeky personality — "It looks like you're deploying an MCP server. Want me to check your config?"
- Good branding angle: "Clippy, but it actually works now — and this time it's Vibbey"

**Why:** Differentiator for VibeOS. Adds personality to developer tooling. Nostalgia hook for marketing/social media virality.

**How to apply:** Build as a browser-based 3D character in the VibeOS frontend during the next VibeOS session. Needs: `clippy.glb` via Three.js, suggestion engine hooked to workspace events, Ollama chat endpoint for freeform questions. Voice block lives at `clippy/dialogue.py`.
