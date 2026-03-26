#!/usr/bin/env python3
"""Devcontainer lifecycle wrapper — flock + boot-id + Taskfile delegation.

Replaces the fragile bash mkdir-lock + /tmp done-marker pattern with:
- fcntl.flock: kernel-managed lock, auto-releases on SIGKILL
- Double-checked locking: check done marker before AND after acquiring lock
- Atomic done-marker writes: temp file + os.rename
- Workspace-local state: .devcontainer/.task/ (not /tmp)

Usage (from devcontainer.json):
    postStartCommand:  python3 .devcontainer/scripts/setup_wrapper.py post-start
    postCreateCommand: python3 .devcontainer/scripts/setup_wrapper.py post-create
"""
import fcntl
import os
import subprocess
import shutil
import sys

WORKSPACE = os.environ.get("CORVIA_WORKSPACE", "/workspaces/corvia-workspace")
TASK_DIR = os.path.join(WORKSPACE, ".devcontainer/.task")
PHASE = sys.argv[1] if len(sys.argv) > 1 else "post-start"
LOCK = os.path.join(TASK_DIR, f"{PHASE}.lock")
DONE = os.path.join(TASK_DIR, f"{PHASE}.done")


VALID_PHASES = ("post-start", "post-create")


def boot_id() -> str:
    """Read kernel boot ID. Falls back to container hostname (changes per
    recreate) rather than a constant like 'unknown' which would silently
    match across reboots and defeat the done-marker mechanism."""
    try:
        with open("/proc/sys/kernel/random/boot_id") as f:
            return f.read().strip()
    except OSError:
        import socket
        return f"host-{socket.gethostname()}"


def _workspace_version() -> str:
    """Get workspace git HEAD so post-start re-runs after git pull."""
    try:
        result = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            capture_output=True, text=True, timeout=5,
            cwd=os.environ.get("CORVIA_WORKSPACE", "/workspaces/corvia-workspace"),
        )
        return result.stdout.strip()[:12] if result.returncode == 0 else ""
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return ""


def _check_done(bid: str) -> bool:
    """Check if this phase already completed for this boot."""
    if os.path.isfile(DONE):
        try:
            with open(DONE) as f:
                return f.read().strip() == bid
        except OSError:
            return False
    return False


def _write_done(bid: str) -> None:
    """Atomically write the done marker (temp + rename)."""
    tmp = DONE + ".tmp"
    with open(tmp, "w") as f:
        f.write(bid)
    os.rename(tmp, DONE)


def main() -> None:
    if PHASE not in VALID_PHASES:
        print(f"ERROR: invalid phase '{PHASE}'. Must be one of: {VALID_PHASES}", file=sys.stderr)
        sys.exit(1)

    os.makedirs(TASK_DIR, exist_ok=True)
    bid = boot_id()
    # post-start should re-run after git pull (new code = new binaries/config).
    # post-create only needs to run once per boot (heavy installs).
    if PHASE == "post-start":
        ws_ver = _workspace_version()
        if ws_ver:
            bid = f"{bid}:{ws_ver}"

    # [SWE-C2] Double-checked locking: check BEFORE lock to avoid blocking
    # when setup already completed (common case on VS Code reconnect).
    if _check_done(bid):
        print(f"{PHASE}: already completed this boot. Skipping.")
        return

    # Acquire exclusive lock. Auto-released on process exit, including SIGKILL.
    # IMPORTANT: Do NOT close lock_fd — closing the fd releases the flock.
    # The fd must stay open for the lock to be held during the entire setup.
    lock_fd = open(LOCK, "w")
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print(f"{PHASE}: another instance running \u2014 waiting...")
        fcntl.flock(lock_fd, fcntl.LOCK_EX)  # block until released

    # [SWE-C2] Re-check after acquiring lock \u2014 first instance may have completed.
    if _check_done(bid):
        print(f"{PHASE}: already completed this boot. Skipping.")
        return

    # [SWE-W2] Use subprocess.run (not os.execvp) for fallback so the done
    # marker is still written on success.
    # [QA-W6] On Taskfile YAML parse error, task exits non-zero. Do NOT
    # silently fall back to bash \u2014 report the error clearly.
    if not shutil.which("task"):
        print(f"WARN: task binary not found \u2014 falling back to bash script")
        rc = subprocess.run(
            ["bash", f".devcontainer/scripts/{PHASE}.sh"],
            cwd=WORKSPACE,
        ).returncode
    else:
        rc = subprocess.run(
            ["task", "-d", f"{WORKSPACE}/.devcontainer", "--output", "group", PHASE],
        ).returncode

    if rc == 0:
        _write_done(bid)
    else:
        print(f"ERROR: {PHASE} failed with exit code {rc}", file=sys.stderr)
        print(f"  Scroll up to see which step failed.", file=sys.stderr)
        print(f"  Re-run all:    task {PHASE} -d .devcontainer", file=sys.stderr)
        print(f"  Re-run a step: task {PHASE}:<step> -d .devcontainer", file=sys.stderr)
        print(f"  List steps:    task --list -d .devcontainer", file=sys.stderr)

    sys.exit(rc)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print(f"\n{PHASE}: interrupted", file=sys.stderr)
        sys.exit(130)
