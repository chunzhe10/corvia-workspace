#!/usr/bin/env python3
"""Install or update the corvia binary from GitHub Releases.

Uses only Python stdlib (no pip dependencies). Supports:
- gh CLI (authenticated, preferred)
- GitHub REST API via urllib (unauthenticated fallback)
- Offline fallback (skip if binary exists)
"""
import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import urllib.error

GH_REPO = "chunzhe10/corvia"
INSTALL_DIR = "/usr/local/bin"
TAG_FILE = "/usr/local/share/corvia-release-tag"
BINARY_NAME = "corvia"


def detect_arch() -> str:
    machine = platform.machine()
    if machine in ("x86_64", "AMD64"):
        return "amd64"
    if machine in ("aarch64", "arm64"):
        return "arm64"
    print(f"error: unsupported architecture: {machine}", file=sys.stderr)
    sys.exit(1)


def installed_tag() -> str | None:
    try:
        with open(TAG_FILE) as f:
            return f.read().strip() or None
    except FileNotFoundError:
        return None


def latest_tag_gh() -> str | None:
    try:
        out = subprocess.check_output(
            ["gh", "release", "view", "--repo", GH_REPO, "--json", "tagName", "-q", ".tagName"],
            text=True, timeout=15, stderr=subprocess.DEVNULL,
        )
        return out.strip() or None
    except (subprocess.CalledProcessError, FileNotFoundError, subprocess.TimeoutExpired):
        return None


def latest_tag_api() -> str | None:
    url = f"https://api.github.com/repos/{GH_REPO}/releases/latest"
    try:
        req = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json"})
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read())
            return data.get("tag_name")
    except (urllib.error.URLError, json.JSONDecodeError, TimeoutError):
        return None


def download_gh(tag: str, asset_name: str, dest: str) -> bool:
    try:
        with tempfile.TemporaryDirectory() as tmpdir:
            subprocess.check_call(
                ["gh", "release", "download", tag, "--repo", GH_REPO,
                 "--pattern", asset_name, "--dir", tmpdir],
                timeout=120, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            src = os.path.join(tmpdir, asset_name)
            if os.path.isfile(src):
                shutil.copy2(src, dest)
                return True
    except (subprocess.CalledProcessError, FileNotFoundError, subprocess.TimeoutExpired):
        pass
    return False


def download_api(tag: str, asset_name: str, dest: str) -> bool:
    url = f"https://api.github.com/repos/{GH_REPO}/releases/tags/{tag}"
    try:
        req = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json"})
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read())
        assets = data.get("assets", [])
        match = next((a for a in assets if a["name"] == asset_name), None)
        if not match:
            return False
        download_url = match["browser_download_url"]
        urllib.request.urlretrieve(download_url, dest)
        return True
    except (urllib.error.URLError, json.JSONDecodeError, StopIteration, TimeoutError):
        return False


def main() -> None:
    arch = detect_arch()
    asset_name = f"corvia-cli-linux-{arch}"
    current_tag = installed_tag()
    binary_path = os.path.join(INSTALL_DIR, BINARY_NAME)

    latest = latest_tag_gh() or latest_tag_api()

    if latest is None:
        if os.path.isfile(binary_path):
            print(f"  network unavailable, using existing binary ({current_tag or 'unknown'})")
            return
        print("error: cannot determine latest release (no network) and no binary installed",
              file=sys.stderr)
        sys.exit(1)

    if current_tag == latest:
        print(f"  corvia {latest}: up to date")
        return

    print(f"  downloading corvia {latest}...")
    with tempfile.NamedTemporaryFile(delete=False, suffix=f".{asset_name}") as tmp:
        tmp_path = tmp.name

    try:
        if not download_gh(latest, asset_name, tmp_path):
            if not download_api(latest, asset_name, tmp_path):
                if os.path.isfile(binary_path):
                    print(f"  download failed, using existing binary ({current_tag or 'unknown'})")
                    return
                print("error: failed to download corvia binary", file=sys.stderr)
                sys.exit(1)

        os.chmod(tmp_path, 0o755)
        dest = os.path.join(INSTALL_DIR, BINARY_NAME)
        try:
            shutil.move(tmp_path, dest)
        except PermissionError:
            subprocess.check_call(["sudo", "cp", tmp_path, dest])
            subprocess.check_call(["sudo", "chmod", "755", dest])
            os.unlink(tmp_path)

        tag_dir = os.path.dirname(TAG_FILE)
        try:
            os.makedirs(tag_dir, exist_ok=True)
            with open(TAG_FILE, "w") as f:
                f.write(latest)
        except PermissionError:
            subprocess.check_call(
                ["sudo", "bash", "-c", f"mkdir -p {tag_dir} && echo '{latest}' > {TAG_FILE}"]
            )

        print(f"  corvia {latest}: installed")

    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)


if __name__ == "__main__":
    main()
