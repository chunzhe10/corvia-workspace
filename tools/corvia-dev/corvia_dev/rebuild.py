"""Build, install, and staleness detection for corvia binaries."""

from __future__ import annotations

import shutil
import subprocess
import stat
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


def install_binaries(
    target_dir: Path,
    install_dir: Path = DEFAULT_INSTALL_DIR,
) -> list[str]:
    """Copy built binaries from target_dir to install_dir.

    Returns list of binary names that were installed.
    """
    installed: list[str] = []
    for name in BINARY_NAMES:
        src = target_dir / name
        if not src.exists():
            continue
        dst = install_dir / name
        shutil.copy2(src, dst)
        dst.chmod(dst.stat().st_mode | stat.S_IEXEC)
        installed.append(name)
    return installed


def cargo_build(workspace_root: Path, release: bool = False) -> bool:
    """Run cargo build for corvia binaries.

    Returns True on success, False on failure.
    """
    # --features corvia-inference/cuda enables llama-cpp CUDA inference for chat.
    # Requires CUDA toolkit (nvcc) at build time; the runtime GPU is provided via docker passthrough.
    cmd = ["cargo", "build", "-p", "corvia-cli", "-p", "corvia-inference",
           "--features", "corvia-inference/cuda"]
    if release:
        cmd.append("--release")

    result = subprocess.run(
        cmd,
        cwd=workspace_root / "repos" / "corvia",
    )
    return result.returncode == 0
