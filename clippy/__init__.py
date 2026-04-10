"""Vibbey — 3D Clippy-lineage assistant for VibeOS first-run.

Package layout (scaffolded 2026-04-10 for Phase B of plans/vibeos-stage4.md):

    clippy/
    ├── __init__.py                  this file
    ├── __main__.py                  entry point: `python3 -m clippy`
    ├── launcher.py                  webkit2gtk window + server + marker
    ├── server.py                    ThreadingHTTPServer + /api/chat proxy
    ├── dialogue.py                  voice block + first-run script (stdlib)
    ├── static/
    │   ├── index.html               Three.js scene + chat UI
    │   ├── main.js                  scene setup, GLB load, chat handlers
    │   └── style.css                VibeOS Neon Grid palette
    ├── autostart/
    │   └── vibeos-first-run.desktop GNOME autostart, gated on marker
    ├── systemd/
    │   └── vibeos-first-run.service user unit alternative
    ├── vibeos-vibbey.desktop        app-grid launcher for manual re-open
    ├── ATTRIBUTION.md               3rd-party asset credits (Sketchfab, fonts)
    └── reference/
        └── concept.jpg              visual reference for Phase 1 direction

First-run flow:
  1. Autostart .desktop fires on GNOME login (or systemd user unit activates)
  2. `python3 -m clippy` picks a free localhost port, starts HTTP server
  3. webkit2gtk window opens at that URL (fallback: system browser)
  4. Three.js loads /clippy.glb (served by server.py from ../clippy.glb)
  5. Idle animation runs via root transform — GLB has no baked clips
  6. Chat bubble POSTs to /api/chat → proxied to Ollama localhost:11434
  7. On window close, ~/.vibeos/first-run-complete marker written
  8. Subsequent logins skip (autostart condition) but app-grid entry remains
"""
