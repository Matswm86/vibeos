# VibeOS Onboarding Agent — Stage 2 (Planned)

This directory will contain the Ollama-powered onboarding agent.

## Planned flow

1. **First boot** — Ollama starts with a small local model (Gemma3 4B or Qwen3 4B)
2. **Hardware detection** — adapts guidance to CPU/RAM/GPU found
3. **Experience detection** — asks a few questions, adjusts tone
4. **Guided Claude Code install + auth** — walks through account creation if needed
5. **MCP configuration** — writes settings, verifies each server responds
6. **Handoff** — "Claude Code is now your primary assistant"

## Why Ollama for onboarding

The task is narrow and structured — a guided conversation with a known flow. A 4B model handles
this on CPU-only hardware. The model doesn't need to be smart; it needs a well-designed system
prompt and a clean shell integration layer.

## Status

Not yet implemented. Contributions welcome.
