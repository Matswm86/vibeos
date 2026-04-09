---
name: VibeOS Clippy Assistant
description: Ollama-powered "Clippy" character for VibeOS — nostalgic UI assistant with contextual MCP workspace suggestions
type: project
---

**Idea**: Add an Ollama-powered "Clippy" assistant character to VibeOS. Nostalgic nod to Microsoft's old paperclip, but actually useful this time.

**Concept**:
- Lives in the VibeOS UI as a small animated character
- Pops up with contextual suggestions based on what user is doing in their managed MCP workspace
- Powered by local Ollama model (lightweight, privacy-first)
- Friendly, slightly cheeky personality — "It looks like you're deploying an MCP server. Want me to check your config?"
- Good branding angle: "Clippy, but it actually works now"

**Why:** Differentiator for VibeOS. Adds personality to developer tooling. Nostalgia hook for marketing/social media virality.

**How to apply:** Build as a React component in the VibeOS frontend during the next VibeOS session. Needs: character animation (CSS/SVG), suggestion engine hooked to workspace events, Ollama chat endpoint for freeform questions.
