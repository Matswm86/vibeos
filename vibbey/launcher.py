"""Vibbey launcher — starts the HTTP server, optionally opens a webkit2gtk window.

Modes (selected by command-line flag):
  --server-only      Start HTTP server only, block forever. Used by vibbey.service.
  --window           Open webkit window (chat UI). Same as default in practice.
  --install-helper   Open a right-docked sidebar loading /install-helper — static
                     Calamares guidance, no chat, no model, used in live session.
  (no flag)          Start server + open chat window (default).

Fallback chain for the window backend:
  1. gi.repository + WebKit2 4.1 (Ubuntu 24.04+)
  2. gi.repository + WebKit2 4.0 (Ubuntu 22.04)
  3. webbrowser.open() — system default browser (last resort)

First-run marker behaviour:
  - Chat mode writes ``~/.vibeos/first-run-complete`` so autostart won't
    re-open Vibbey after the user closes it.
  - Install-helper mode does NOT write the marker — the real Vibbey chat
    should still greet the user on first login to the installed system.
"""

import sys
import threading
import webbrowser
from pathlib import Path

from .server import start_server

FIRST_RUN_MARKER = Path.home() / ".vibeos" / "first-run-complete"
WINDOW_TITLE = "Vibbey — VibeOS Assistant"
WINDOW_TITLE_INSTALL = "Vibbey — installing VibeOS"
WINDOW_WIDTH = 480
WINDOW_HEIGHT = 640
SIDEBAR_WIDTH = 420


def _try_webkit2(url: str, *, title: str, install_helper: bool) -> bool:
    """Try to open a webkit2gtk window. Return True on success.

    In install-helper mode, the window is docked to the right edge of the
    primary monitor at full height so it sits alongside Calamares without
    stealing focus. In chat mode, a centered floating window.
    """
    try:
        import gi
    except ImportError:
        return False

    webkit = None
    gtk = None
    gdk = None
    for webkit_version in ("4.1", "4.0"):
        try:
            gi.require_version("Gtk", "3.0")
            gi.require_version("Gdk", "3.0")
            gi.require_version("WebKit2", webkit_version)
            from gi.repository import Gtk as _gtk  # type: ignore
            from gi.repository import Gdk as _gdk  # type: ignore
            from gi.repository import WebKit2 as _webkit  # type: ignore
            gtk = _gtk
            gdk = _gdk
            webkit = _webkit
            break
        except (ValueError, ImportError):
            continue

    if gtk is None or webkit is None or gdk is None:
        return False

    win = gtk.Window(title=title)
    # Set a stable WM_CLASS so KWin / window rules can match reliably
    wm_class = "vibbey-install" if install_helper else "vibbey"
    win.set_wmclass(wm_class, wm_class)
    win.connect("destroy", gtk.main_quit)

    if install_helper:
        # Right-docked sidebar: full monitor height, SIDEBAR_WIDTH wide,
        # pinned to the right edge of the primary monitor.
        display = gdk.Display.get_default()
        monitor = display.get_primary_monitor() if display else None
        if monitor is None and display is not None and display.get_n_monitors() > 0:
            monitor = display.get_monitor(0)
        if monitor is not None:
            geo = monitor.get_geometry()
            win.set_default_size(SIDEBAR_WIDTH, geo.height)
            win.move(geo.x + geo.width - SIDEBAR_WIDTH, geo.y)
        else:
            win.set_default_size(SIDEBAR_WIDTH, 900)
            win.move(0, 0)
        # Don't pin above Calamares — Calamares is the primary action,
        # the sidebar should be normal-stacking so focus works naturally.
        win.set_skip_taskbar_hint(False)
        win.set_type_hint(gdk.WindowTypeHint.NORMAL)
    else:
        # Chat mode: centered floating window, resizable, decorated, movable.
        win.set_default_size(WINDOW_WIDTH, WINDOW_HEIGHT)
        win.set_position(gtk.WindowPosition.CENTER)
        win.set_type_hint(gdk.WindowTypeHint.NORMAL)

    view = webkit.WebView()
    view.load_uri(url)
    win.add(view)
    win.show_all()
    gtk.main()
    return True


def _mark_first_run_complete() -> None:
    FIRST_RUN_MARKER.parent.mkdir(parents=True, exist_ok=True)
    FIRST_RUN_MARKER.write_text("Vibbey first-run completed.\n")


def _open_window(url: str, *, title: str, install_helper: bool) -> None:
    """Open the Vibbey window via webkit or system browser. Blocks until closed."""
    if _try_webkit2(url, title=title, install_helper=install_helper):
        print("[vibbey] webkit2gtk window closed")
    else:
        print("[vibbey] webkit2gtk unavailable — falling back to system browser")
        webbrowser.open(url)
        print("[vibbey] press Ctrl-C when done (browser path has no lifecycle signal)")
        try:
            threading.Event().wait()
        except KeyboardInterrupt:
            pass


def main() -> int:
    args = sys.argv[1:]
    server_only = "--server-only" in args
    install_helper = "--install-helper" in args

    server, port = start_server()
    url_root = f"http://127.0.0.1:{port}/"
    url = f"{url_root}install-helper" if install_helper else url_root
    print(f"[vibbey] server up at {url_root}")

    server_thread = threading.Thread(target=server.serve_forever, daemon=True)
    server_thread.start()

    if server_only:
        print("[vibbey] running in server-only mode (managed by systemd)")
        try:
            server_thread.join()
        except KeyboardInterrupt:
            pass
        finally:
            server.shutdown()
        return 0

    title = WINDOW_TITLE_INSTALL if install_helper else WINDOW_TITLE
    try:
        _open_window(url, title=title, install_helper=install_helper)
    finally:
        server.shutdown()
        # Only mark first-run complete for real chat mode — the install
        # helper runs in the live session where no first-run state matters.
        if not install_helper:
            _mark_first_run_complete()
            print(f"[vibbey] first-run marker written at {FIRST_RUN_MARKER}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
