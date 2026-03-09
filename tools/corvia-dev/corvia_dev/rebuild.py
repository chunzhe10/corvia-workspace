"""Build, install, and staleness detection for corvia binaries."""

from __future__ import annotations

from pathlib import Path

BINARY_NAMES = ["corvia", "corvia-inference"]
DEFAULT_INSTALL_DIR = Path("/usr/local/bin")


def check_staleness(
    workspace_root: Path,
    target_dir: Path | None = None,
    install_dir: Path = DEFAULT_INSTALL_DIR,
) -> list[str]:
    """Check which installed binaries are older than their local build.

    Returns a list of binary names that are stale (target is newer than installed).
    Returns empty list if no target binaries exist or all are up to date.
    """
    if target_dir is None:
        target_dir = workspace_root / "repos" / "corvia" / "target" / "debug"

    stale: list[str] = []
    for name in BINARY_NAMES:
        target = target_dir / name
        installed = install_dir / name
        if not target.exists() or not installed.exists():
            continue
        if target.stat().st_mtime > installed.stat().st_mtime:
            stale.append(name)
    return stale
