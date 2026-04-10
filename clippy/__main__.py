"""Entry point for ``python3 -m clippy``.

Before importing the launcher (which pulls in GTK/WebKit via gi), make sure
the current Python interpreter can actually import ``gi``. On Ubuntu 24.04
boxes where the system ``python3`` has been overridden by a custom build
(e.g. a manually-installed python3.11 aliased via ``update-alternatives``),
the apt ``python3-gi`` package only ships the ``_gi.cpython-312-*.so``
binary — so ``import gi`` under the aliased python raises a misleading
"circular import" ImportError.

Detect that mismatch and transparently re-exec with a sibling interpreter
that has working ``gi``. Fresh VibeOS ISOs never hit this path.
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

    # Preference: newer first. Cover 3.10/3.11/3.12/3.13 so we don't have to
    # revisit this when distros bump.
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
            os.execv(path, [path, "-m", "clippy", *sys.argv[1:]])
    # No working sibling found — let launcher fall through to webbrowser.
    sys.stdout.write(
        "[vibbey] gi unavailable and no sibling Python found — "
        "falling back to system browser\n"
    )
    sys.stdout.flush()


_maybe_reexec_with_working_gi()

from .launcher import main  # noqa: E402

if __name__ == "__main__":
    raise SystemExit(main())
