"""Build, install, and staleness detection for corvia binaries.

Single source of truth for binary names, paths, and versioning.
Both corvia-dev CLI and devcontainer bash scripts delegate here.
"""

from __future__ import annotations

import json
import os
import platform
import re
import signal
import shutil
import stat
import subprocess
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.request import urlopen, Request
from urllib.error import URLError

# ---------------------------------------------------------------------------
# Constants — single source of truth
# ---------------------------------------------------------------------------

#: Binaries built by `cargo build -p corvia-cli -p corvia-inference`.
BINARY_NAMES = ["corvia", "corvia-inference"]

#: Adapter binaries (built separately, included in release assets).
ADAPTER_NAMES = ["corvia-adapter-basic", "corvia-adapter-git"]

#: All binaries expected in a complete installation.
ALL_BINARY_NAMES = BINARY_NAMES + ADAPTER_NAMES

DEFAULT_INSTALL_DIR = Path("/usr/local/bin")
RELEASE_TAG_FILE = Path("/usr/local/share/corvia-release-tag")
GH_REPO = "chunzhe10/corvia"

#: ORT execution provider shared libraries required for GPU inference.
ORT_PROVIDER_LIBS = [
    "libonnxruntime_providers_shared.so",
    "libonnxruntime_providers_cuda.so",
    "libonnxruntime_providers_openvino.so",
]
ORT_LIB_DIR = Path("/usr/lib/x86_64-linux-gnu")


# ---------------------------------------------------------------------------
# Architecture detection
# ---------------------------------------------------------------------------

def _detect_arch_suffix() -> str:
    machine = platform.machine()
    if machine == "x86_64":
        return "amd64"
    if machine == "aarch64":
        return "arm64"
    raise RuntimeError(f"Unsupported architecture: {machine}")


# ---------------------------------------------------------------------------
# Network / GitHub helpers
# ---------------------------------------------------------------------------

def _gh_available() -> bool:
    """Check if gh CLI is authenticated."""
    try:
        result = subprocess.run(
            ["gh", "auth", "status"],
            capture_output=True, timeout=5,
        )
        return result.returncode == 0
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False


def _network_available() -> bool:
    """Quick check for network connectivity."""
    try:
        urlopen(Request("https://github.com", method="HEAD"), timeout=3)
        return True
    except (URLError, OSError):
        return False


def get_latest_release_tag() -> str | None:
    """Fetch the latest release tag from GitHub.

    Tries gh CLI first (faster, authenticated), falls back to public API.
    Returns None if unreachable.
    """
    # Try gh CLI
    if _gh_available():
        try:
            result = subprocess.run(
                ["gh", "release", "view", "--repo", GH_REPO,
                 "--json", "tagName", "-q", ".tagName"],
                capture_output=True, text=True, timeout=10,
            )
            if result.returncode == 0 and result.stdout.strip():
                return result.stdout.strip()
        except subprocess.TimeoutExpired:
            pass

    # Fall back to public API
    try:
        url = f"https://api.github.com/repos/{GH_REPO}/releases/latest"
        with urlopen(url, timeout=5) as resp:
            data = json.loads(resp.read())
            tag = data.get("tag_name", "")
            return tag if tag else None
    except (URLError, OSError, json.JSONDecodeError, KeyError):
        return None


# ---------------------------------------------------------------------------
# Release download
# ---------------------------------------------------------------------------

def _download_file(url: str, dest: Path) -> bool:
    """Download a single file. Returns True on success."""
    try:
        result = subprocess.run(
            ["curl", "-fsL", "--retry", "3", "--retry-delay", "2",
             "-o", str(dest), url],
            capture_output=True, timeout=120,
        )
        return result.returncode == 0
    except subprocess.TimeoutExpired:
        return False


def _stop_services_if_needed(install_dir: Path = DEFAULT_INSTALL_DIR) -> None:
    """Stop corvia-dev managed services if any target binaries are running.

    This prevents 'Text file busy' errors when overwriting running binaries.
    """
    from corvia_dev.manager import DEFAULT_STATE_PATH
    state_path = DEFAULT_STATE_PATH
    if not state_path.exists():
        return

    try:
        data = json.loads(state_path.read_text())
        manager_pid = data.get("manager", {}).get("pid")
        if manager_pid:
            os.kill(int(manager_pid), signal.SIGTERM)
            time.sleep(2)
    except (json.JSONDecodeError, ValueError, ProcessLookupError, OSError):
        pass

    # Also kill any stray corvia processes holding binaries open
    for name in ["corvia serve", "corvia-inference serve"]:
        subprocess.run(
            ["pkill", "-9", "-f", name],
            capture_output=True,
        )


def download_release(
    tag: str | None = None,
    install_dir: Path = DEFAULT_INSTALL_DIR,
) -> list[str]:
    """Download and install release binaries from GitHub.

    Downloads ALL_BINARY_NAMES + ORT provider libs.
    Writes the release tag to RELEASE_TAG_FILE on success.
    Returns list of installed binary names.
    """
    arch = _detect_arch_suffix()
    tmpdir = Path(tempfile.mkdtemp())

    try:
        # Build asset map: binary_name -> asset_filename
        assets: dict[str, str] = {}
        for name in ALL_BINARY_NAMES:
            if name == "corvia":
                assets[name] = f"corvia-cli-linux-{arch}"
            else:
                assets[name] = f"{name}-linux-{arch}"

        # ORT libs (best-effort)
        ort_assets: dict[str, str] = {}
        for lib in ORT_PROVIDER_LIBS:
            base = lib.removesuffix(".so")
            ort_assets[lib] = f"{base}-linux-{arch}.so"

        if _gh_available() and tag:
            # Use gh release download (single command, handles auth)
            patterns = []
            for asset_name in list(assets.values()) + list(ort_assets.values()):
                patterns.extend(["--pattern", asset_name])
            subprocess.run(
                ["gh", "release", "download", tag, "--repo", GH_REPO,
                 "--dir", str(tmpdir)] + patterns,
                capture_output=True, timeout=120,
            )
        else:
            # Parallel curl downloads
            base_url = f"https://github.com/{GH_REPO}/releases/latest/download"
            all_downloads = list(assets.values()) + list(ort_assets.values())

            with ThreadPoolExecutor(max_workers=8) as pool:
                futures = {
                    name: pool.submit(
                        _download_file,
                        f"{base_url}/{name}",
                        tmpdir / name,
                    )
                    for name in all_downloads
                }
                try:
                    results = {name: fut.result() for name, fut in futures.items()}
                except Exception as e:
                    print(f"    download failed: {e}")
                    return []

            # Check required binaries succeeded
            for name in assets.values():
                if not results.get(name, False):
                    print(f"    FAILED to download {name}")
                    return []

        # Stop running services if binaries are in use (Text file busy).
        # Uses the process manager state file to find the PID.
        _stop_services_if_needed(install_dir)

        # Install binaries
        installed: list[str] = []
        for binary_name, asset_name in assets.items():
            src = tmpdir / asset_name
            if not src.exists():
                continue
            dst = install_dir / binary_name
            try:
                shutil.copy2(src, dst)
            except OSError:
                # Text file busy — try removing first, then copy
                dst.unlink(missing_ok=True)
                shutil.copy2(src, dst)
            dst.chmod(dst.stat().st_mode | stat.S_IEXEC)
            installed.append(binary_name)

        # Install ORT libs (best-effort)
        ort_installed = False
        for lib_name, asset_name in ort_assets.items():
            src = tmpdir / asset_name
            if not src.exists():
                continue
            dst = ORT_LIB_DIR / lib_name
            shutil.copy2(src, dst)
            ort_installed = True

        if ort_installed:
            subprocess.run(["ldconfig"], check=False, timeout=30)

        # Cache the installed tag
        if tag and installed:
            RELEASE_TAG_FILE.parent.mkdir(parents=True, exist_ok=True)
            RELEASE_TAG_FILE.write_text(f"{tag}\n")

        return installed

    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)


# ---------------------------------------------------------------------------
# Ensure binaries are up to date (called from bash ensure_corvia)
# ---------------------------------------------------------------------------

def ensure_up_to_date(
    install_dir: Path = DEFAULT_INSTALL_DIR,
) -> str:
    """Check and update release binaries if needed.

    Returns:
        "up_to_date"  — binaries current, no action taken
        "updated"     — downloaded and installed newer release
        "offline_ok"  — no network but binaries exist
        "missing"     — no network and binaries missing
    """
    all_present = all(
        (install_dir / name).exists() for name in ALL_BINARY_NAMES
    )

    # Check cached tag
    cached_tag = ""
    if RELEASE_TAG_FILE.exists():
        cached_tag = RELEASE_TAG_FILE.read_text().strip()

    is_release = bool(re.match(r"^v\d", cached_tag))

    # Try to get latest tag
    latest_tag = get_latest_release_tag()

    if latest_tag is None:
        # No network
        if all_present:
            return "offline_ok"
        return "missing"

    # All binaries present and tag matches latest release
    if all_present and is_release and cached_tag == latest_tag:
        return "up_to_date"

    # Need to download
    installed = download_release(tag=latest_tag, install_dir=install_dir)
    if installed:
        return "updated"

    # Download failed
    if all_present:
        return "offline_ok"  # keep existing
    return "missing"


# ---------------------------------------------------------------------------
# ORT provider lib recovery (from local builds)
# ---------------------------------------------------------------------------

def ensure_ort_libs(workspace_root: Path) -> bool:
    """Ensure ORT provider libs are in the system lib path.

    Checks ORT_LIB_DIR for each lib. If missing, copies from the most
    recent cargo build (release first, then debug). Returns True if any
    lib was installed.
    """
    # Only relevant on amd64
    if platform.machine() != "x86_64":
        return False

    missing = [lib for lib in ORT_PROVIDER_LIBS if not (ORT_LIB_DIR / lib).exists()]
    if not missing:
        return False

    # Try release first, fall back to debug
    corvia_dir = workspace_root / "repos" / "corvia"
    target_dir = corvia_dir / "target" / "release"
    if not target_dir.exists():
        target_dir = corvia_dir / "target" / "debug"

    any_installed = False
    for lib_name in missing:
        src = target_dir / lib_name
        if not src.exists() and not src.is_symlink():
            continue
        real_src = src.resolve()
        if not real_src.exists():
            continue
        dst = ORT_LIB_DIR / lib_name
        shutil.copy2(real_src, dst)
        any_installed = True

    if any_installed:
        subprocess.run(["ldconfig"], check=False, timeout=30)

    return any_installed


# ---------------------------------------------------------------------------
# Local build install (called by corvia-dev rebuild / up)
# ---------------------------------------------------------------------------

def install_local_binaries(
    target_dir: Path,
    install_dir: Path = DEFAULT_INSTALL_DIR,
) -> list[str]:
    """Copy locally-built binaries from target_dir to install_dir.

    Only copies BINARY_NAMES (corvia, corvia-inference) since adapters
    are not part of the standard `cargo build` invocation.

    Invalidates the release tag cache so ensure_up_to_date() knows these
    are local builds, not release downloads.

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

    # Invalidate release tag cache
    if installed:
        RELEASE_TAG_FILE.parent.mkdir(parents=True, exist_ok=True)
        RELEASE_TAG_FILE.write_text("local-build\n")

    # Install ORT provider libs from build output
    for lib_name in ORT_PROVIDER_LIBS:
        src = target_dir / lib_name
        if not src.exists():
            continue
        real_src = src.resolve()
        if not real_src.exists():
            continue
        dst = ORT_LIB_DIR / lib_name
        shutil.copy2(real_src, dst)

    subprocess.run(["ldconfig"], check=False, timeout=30)

    return installed


# Keep old name as alias for backward compat with cli.py imports
install_binaries = install_local_binaries


# ---------------------------------------------------------------------------
# Staleness detection (local build vs installed)
# ---------------------------------------------------------------------------

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
    # TODO: also check adapters (different target dirs)
    return stale


# ---------------------------------------------------------------------------
# Cargo build
# ---------------------------------------------------------------------------

def cargo_build(workspace_root: Path, release: bool = False) -> bool:
    """Run cargo build for corvia binaries.

    Returns True on success, False on failure.
    """
    cmd = ["cargo", "build", "-p", "corvia-cli", "-p", "corvia-inference",
           "--features", "corvia-inference/cuda"]
    if release:
        cmd.append("--release")

    result = subprocess.run(
        cmd,
        cwd=workspace_root / "repos" / "corvia",
    )
    return result.returncode == 0
