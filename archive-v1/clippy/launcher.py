"""Vibbey launcher — starts the HTTP server, opens a webkit2gtk window.

Fallback chain for the window backend:
  1. gi.repository + WebKit2 4.1 (Ubuntu 24.04+)
  2. gi.repository + WebKit2 4.0 (Ubuntu 22.04)
  3. webbrowser.open() — system default browser (last resort)

On clean exit, writes ``~/.vibeos/first-run-complete`` so the autostart entry
won't re-launch Vibbey on subsequent logins. Users can always re-launch
manually via the ``Vibbey`` app-grid entry or ``python3 -m clippy``.
"""

import sys
import threading
import webbrowser
from pathlib import Path

from .server import start_server

FIRST_RUN_MARKER = Path.home() / ".vibeos" / "first-run-complete"
WINDOW_TITLE = "Vibbey — VibeOS Assistant"
WINDOW_WIDTH = 420
WINDOW_HEIGHT = 560


def _try_webkit2(url: str) -> bool:
    """Try to open a webkit2gtk window. Return True on success.

    Tries WebKit2 4.1 first (Ubuntu 24.04+), then 4.0 (Ubuntu 22.04). If
    neither is available or GTK fails to init, return False so the caller
    can fall back to webbrowser.open().
    """
    try:
        import gi
    except ImportError:
        return False

    webkit = None
    gtk = None
    for webkit_version in ("4.1", "4.0"):
        try:
            gi.require_version("Gtk", "3.0")
            gi.require_version("WebKit2", webkit_version)
            from gi.repository import Gtk as _gtk  # type: ignore
            from gi.repository import WebKit2 as _webkit  # type: ignore
            gtk = _gtk
            webkit = _webkit
            break
        except (ValueError, ImportError):
            continue

    if gtk is None or webkit is None:
        return False

    win = gtk.Window(title=WINDOW_TITLE)
    win.set_default_size(WINDOW_WIDTH, WINDOW_HEIGHT)
    win.set_keep_above(True)  # always-on-top, Clippy-style
    win.connect("destroy", gtk.main_quit)

    view = webkit.WebView()
    view.load_uri(url)
    win.add(view)

    win.show_all()
    gtk.main()
    return True


def _mark_first_run_complete() -> None:
    FIRST_RUN_MARKER.parent.mkdir(parents=True, exist_ok=True)
    FIRST_RUN_MARKER.write_text("Vibbey first-run completed.\n")


def main() -> int:
    server, port = start_server()
    url = f"http://127.0.0.1:{port}/"
    print(f"[vibbey] server up at {url}")

    # Server runs in a daemon thread so we can block on the window.
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    try:
        if _try_webkit2(url):
            print("[vibbey] webkit2gtk window closed")
        else:
            print("[vibbey] webkit2gtk unavailable — falling back to system browser")
            webbrowser.open(url)
            print("[vibbey] press Ctrl-C when done (browser path has no lifecycle signal)")
            try:
                thread.join()
            except KeyboardInterrupt:
                pass
    finally:
        server.shutdown()
        _mark_first_run_complete()
        print(f"[vibbey] marker written at {FIRST_RUN_MARKER}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
