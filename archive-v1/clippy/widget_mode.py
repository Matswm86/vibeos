"""Vibbey widget-mode launcher — chrome-stripped, bottom-right desktop widget.

Run with:
    python3 -m clippy.widget_mode

Differences from the standard ``launcher.py``:
  * No window decorations (no titlebar, no borders, no close button)
  * Transparent window background via RGBA visual — the character and speech
    bubble float directly on the desktop
  * Skip taskbar + pager hints — no Alt-Tab entry, no window switcher entry
  * Keep-above + UTILITY type hint — always visible, stays out of Alt-Tab
  * Anchored to the bottom-right of the primary monitor, above the taskbar
  * Appends ``?widget=1`` to the URL so the frontend applies widget-mode CSS

If the chrome-strip succeeds, Vibbey appears as a floating character anchored
to the lower-right of the screen, not as a normal application window.

This module is a PREVIEW build. Once approved, its behavior will fold into
``launcher.py`` and become the default.
"""

import os
import subprocess
import sys


def _maybe_reexec_with_working_gi() -> None:
    """Re-exec under a sibling Python if this one can't import ``gi``.

    Mirrors ``clippy.__main__._maybe_reexec_with_working_gi`` but targets
    ``clippy.widget_mode`` as the re-exec entry point so the widget mode
    survives the Ubuntu 24.04 python3.11/3.12 gi-binding mismatch.
    """
    try:
        import gi  # noqa: F401
        return
    except ImportError:
        pass

    candidates = ("python3.13", "python3.12", "python3.11", "python3.10")
    for name in candidates:
        path = f"/usr/bin/{name}"
        if not os.path.exists(path):
            continue
        if os.path.realpath(path) == os.path.realpath(sys.executable):
            continue
        check = subprocess.run(
            [path, "-c", "import gi; gi.require_version('Gtk', '3.0')"],
            capture_output=True,
        )
        if check.returncode == 0:
            sys.stdout.write(
                f"[vibbey-widget] re-execing under {path} "
                f"(current {sys.executable} can't import gi)\n"
            )
            sys.stdout.flush()
            # -u = unbuffered stdout so logs survive to whatever's reading us
            os.execv(path, [path, "-u", "-m", "clippy.widget_mode", *sys.argv[1:]])
    sys.stdout.write(
        "[vibbey-widget] gi unavailable and no sibling Python found — "
        "falling back to system browser\n"
    )
    sys.stdout.flush()


# Must run before importing .server (which is harmless) — ordering here just
# matches __main__.py for consistency.
_maybe_reexec_with_working_gi()

import threading  # noqa: E402
import webbrowser  # noqa: E402
from pathlib import Path  # noqa: E402

from .server import start_server  # noqa: E402

FIRST_RUN_MARKER = Path.home() / ".vibeos" / "first-run-complete"
WIDGET_WIDTH = 360
WIDGET_HEIGHT = 480
MARGIN_RIGHT = 24
MARGIN_BOTTOM = 72  # clear the GNOME top/bottom bar and dock


def _try_widget_window(url: str) -> bool:
    """Open Vibbey as a true floating desktop widget via layer-shell.

    Uses the Wayland ``layer-shell`` protocol (supported by wlroots, COSMIC,
    KDE KWin, Sway, Hyprland) to anchor Vibbey to the bottom-right of the
    screen as a first-class desktop-layer surface — not a toplevel window.

    Layer-shell surfaces have no titlebar, no border, no taskbar presence,
    no Alt-Tab entry, and cannot be moved/resized by the user. They're the
    correct protocol for panels, docks, notifications, and desktop widgets.

    Returns True if the layer-shell surface launched, False if layer-shell
    is unavailable (e.g. GNOME Mutter, X11) so the caller can fall back.
    """
    try:
        import gi
    except ImportError:
        return False

    # Require GTK3 + Gdk + WebKit2 + GtkLayerShell
    webkit = None
    gtk = None
    gdk = None
    layer_shell = None
    for webkit_version in ("4.1", "4.0"):
        try:
            gi.require_version("Gtk", "3.0")
            gi.require_version("Gdk", "3.0")
            gi.require_version("WebKit2", webkit_version)
            gi.require_version("GtkLayerShell", "0.1")
            from gi.repository import Gdk as _gdk  # type: ignore
            from gi.repository import Gtk as _gtk  # type: ignore
            from gi.repository import GtkLayerShell as _layer  # type: ignore
            from gi.repository import WebKit2 as _webkit  # type: ignore
            gtk = _gtk
            gdk = _gdk
            webkit = _webkit
            layer_shell = _layer
            break
        except (ValueError, ImportError):
            continue

    if gtk is None or webkit is None or gdk is None or layer_shell is None:
        return False

    # Layer-shell requires a Wayland display. If we're on X11 (or XWayland
    # via GDK_BACKEND=x11), skip this path entirely so the caller uses the
    # X11-friendly fallback instead of triggering a flood of GTK criticals.
    display = gdk.Display.get_default()
    if display is None or "Wayland" not in type(display).__name__:
        sys.stdout.write(
            f"[vibbey-widget] display is {type(display).__name__ if display else 'None'}, "
            "skipping layer-shell\n"
        )
        sys.stdout.flush()
        return False

    if not layer_shell.is_supported():
        sys.stdout.write("[vibbey-widget] layer-shell not advertised by compositor\n")
        sys.stdout.flush()
        return False

    win = gtk.Window(type=gtk.WindowType.TOPLEVEL)
    win.set_default_size(WIDGET_WIDTH, WIDGET_HEIGHT)

    # ── Transparent background (for the RGBA compositor channel) ──
    screen = win.get_screen()
    visual = screen.get_rgba_visual()
    if visual is not None and screen.is_composited():
        win.set_visual(visual)
    win.set_app_paintable(True)

    # ── Initialise this window as a layer-shell surface ───────────
    layer_shell.init_for_window(win)
    layer_shell.set_layer(win, layer_shell.Layer.TOP)
    layer_shell.set_namespace(win, "vibeos-vibbey")

    # Anchor bottom + right → bottom-right corner
    layer_shell.set_anchor(win, layer_shell.Edge.BOTTOM, True)
    layer_shell.set_anchor(win, layer_shell.Edge.RIGHT, True)
    layer_shell.set_anchor(win, layer_shell.Edge.TOP, False)
    layer_shell.set_anchor(win, layer_shell.Edge.LEFT, False)

    # Margins from the edges (compositor handles the positioning)
    layer_shell.set_margin(win, layer_shell.Edge.BOTTOM, MARGIN_BOTTOM)
    layer_shell.set_margin(win, layer_shell.Edge.RIGHT, MARGIN_RIGHT)

    # No exclusive zone — we don't want to push other windows around,
    # Vibbey floats over whatever is below her.
    layer_shell.set_exclusive_zone(win, 0)

    # Keyboard interactivity — ON_DEMAND means the chat input gets focus
    # when the user clicks it, but Vibbey doesn't steal focus otherwise.
    try:
        layer_shell.set_keyboard_mode(win, layer_shell.KeyboardMode.ON_DEMAND)
    except AttributeError:
        # Older layer-shell (< 0.7) — fall back to boolean interactivity
        try:
            layer_shell.set_keyboard_interactivity(win, True)
        except Exception:
            pass

    win.connect("destroy", gtk.main_quit)

    # ── WebView with transparent background ─────────────────────
    view = webkit.WebView()
    try:
        view.set_background_color(gdk.RGBA(0, 0, 0, 0))
    except Exception:
        pass  # fallback: CSS paints over any solid bg
    sep = "&" if "?" in url else "?"
    view.load_uri(f"{url}{sep}widget=1")
    win.add(view)

    win.show_all()
    gtk.main()
    return True


def _try_fallback_window(url: str) -> bool:
    """Fallback for compositors without layer-shell (GNOME Mutter, X11).

    Opens a chrome-stripped borderless window via set_decorated(False) +
    UTILITY type hint. This is the best we can do on Wayland compositors
    that don't implement layer-shell. Positioning is compositor-dependent.
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
            from gi.repository import Gdk as _gdk  # type: ignore
            from gi.repository import Gtk as _gtk  # type: ignore
            from gi.repository import WebKit2 as _webkit  # type: ignore
            gtk = _gtk
            gdk = _gdk
            webkit = _webkit
            break
        except (ValueError, ImportError):
            continue

    if gtk is None or webkit is None or gdk is None:
        return False

    display = gdk.Display.get_default()
    is_x11 = display is not None and "X11" in type(display).__name__
    sys.stdout.write(
        f"[vibbey-widget] using fallback toplevel "
        f"(display={type(display).__name__ if display else 'None'}, x11={is_x11})\n"
    )
    sys.stdout.flush()

    win = gtk.Window(type=gtk.WindowType.TOPLEVEL)
    win.set_default_size(WIDGET_WIDTH, WIDGET_HEIGHT)
    win.set_decorated(False)
    win.set_resizable(False)
    win.set_skip_taskbar_hint(True)
    win.set_skip_pager_hint(True)
    win.set_keep_above(True)
    # SPLASHSCREEN type-hint is the most reliably undecorated across WMs
    # and avoids the small titlebar some compositors add to UTILITY windows.
    win.set_type_hint(gdk.WindowTypeHint.SPLASHSCREEN)

    screen = win.get_screen()
    visual = screen.get_rgba_visual()
    if visual is not None and screen.is_composited():
        win.set_visual(visual)
    win.set_app_paintable(True)

    # Bottom-right anchoring via X11 positioning. Works on X11 and on
    # XWayland (COSMIC/GNOME Mutter/KWin via GDK_BACKEND=x11). Wayland
    # native clients can't request position, which is why we needed
    # layer-shell for the primary path.
    monitor = display.get_primary_monitor() if display else None
    if monitor:
        geo = monitor.get_geometry()
        x = geo.x + geo.width - WIDGET_WIDTH - MARGIN_RIGHT
        y = geo.y + geo.height - WIDGET_HEIGHT - MARGIN_BOTTOM
        # Set position BEFORE show_all so the first paint is at the right place.
        win.move(x, y)
        sys.stdout.write(f"[vibbey-widget] positioning at ({x}, {y})\n")
        sys.stdout.flush()

    win.connect("destroy", gtk.main_quit)

    # Re-apply keep_above after realize in case the WM resets it.
    def _reapply_above(w):
        w.set_keep_above(True)
        if monitor:
            geo2 = monitor.get_geometry()
            w.move(
                geo2.x + geo2.width - WIDGET_WIDTH - MARGIN_RIGHT,
                geo2.y + geo2.height - WIDGET_HEIGHT - MARGIN_BOTTOM,
            )
    win.connect("realize", _reapply_above)

    view = webkit.WebView()
    try:
        view.set_background_color(gdk.RGBA(0, 0, 0, 0))
    except Exception:
        pass
    sep = "&" if "?" in url else "?"
    view.load_uri(f"{url}{sep}widget=1")
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
    print(f"[vibbey-widget] server up at {url}")
    print(f"[vibbey-widget] launching as bottom-right desktop widget")

    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    try:
        if _try_widget_window(url):
            print("[vibbey-widget] layer-shell widget closed")
        elif _try_fallback_window(url):
            print("[vibbey-widget] fallback window closed")
        else:
            print("[vibbey-widget] webkit2gtk unavailable — falling back to system browser")
            webbrowser.open(f"{url}?widget=1")
            try:
                thread.join()
            except KeyboardInterrupt:
                pass
    finally:
        server.shutdown()
        _mark_first_run_complete()
        print(f"[vibbey-widget] marker written at {FIRST_RUN_MARKER}")

    return 0


if __name__ == "__main__":
    # Allow `python3 -m clippy.widget_mode` without the auto-reexec dance
    # that ``__main__.py`` does — if the user's python can't import gi,
    # they'll get an honest ImportError and can re-run via __main__.py.
    sys.exit(main())
