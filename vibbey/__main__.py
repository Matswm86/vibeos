"""Entry point for ``python3 -m vibbey``.

Flags:
  --server-only   Start HTTP server only, no GUI window. Used by vibbey.service.
  --window        Open the GUI window connected to a running server (or start one).
  (no flag)       Full launcher: start server + open window (default).

Before importing the launcher (which pulls in GTK/WebKit via gi), check that
the current Python can actually import ``gi``. On Ubuntu 24.04 boxes where a
custom python3.11 alias is active, the apt python3-gi package ships
_gi.cpython-312-*.so only — import gi under the aliased python raises a
misleading "circular import" ImportError. Detect that and re-exec under a
sibling interpreter that has working gi.
"""

import os
import subprocess
import sys


def _maybe_reexec_with_working_gi() -> None:
    """Re-exec under a sibling Python if this one can't import ``gi``."""
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
                f"[vibbey] re-execing under {path} "
                f"(current {sys.executable} can't import gi)\n"
            )
            sys.stdout.flush()
            os.execv(path, [path, "-m", "vibbey", *sys.argv[1:]])
    sys.stdout.write(
        "[vibbey] gi unavailable and no sibling Python found — "
        "falling back to system browser\n"
    )
    sys.stdout.flush()


_maybe_reexec_with_working_gi()

from .launcher import main  # noqa: E402

if __name__ == "__main__":
    raise SystemExit(main())
