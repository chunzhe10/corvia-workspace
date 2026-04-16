#!/usr/bin/env python3
"""Devcontainer setup telemetry — buffer step timing, ingest into corvia.

Records structured telemetry from each setup task BEFORE corvia is running,
then ingests into corvia's knowledge base via MCP once the server is up.

Usage:
    setup_telemetry.py init --trigger post-start     # Start session
    setup_telemetry.py record "step-name" -- cmd...  # Time a command
    setup_telemetry.py finalize                      # End session, prune old files
    setup_telemetry.py ingest                        # Send to corvia via MCP
    setup_telemetry.py check-ingested                # Exit 0 if current boot ingested

No pip dependencies — Python stdlib only.
"""
import json
import os
import platform
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

WORKSPACE = os.environ.get("CORVIA_WORKSPACE", "/workspaces/corvia-workspace")
TELEMETRY_DIR = os.path.join(WORKSPACE, ".devcontainer/.task-telemetry")
MAX_FILES = 20  # Retention: keep this many telemetry files


def _boot_id() -> str:
    try:
        with open("/proc/sys/kernel/random/boot_id") as f:
            return f.read().strip()
    except OSError:
        import socket
        return f"host-{socket.gethostname()}"


def _session_path(bid: str | None = None, trigger: str | None = None) -> str:
    bid = bid or _boot_id()
    suffix = f"-{trigger}" if trigger else ""
    return os.path.join(TELEMETRY_DIR, f"{bid}{suffix}.json")


def _read_session(path: str) -> dict | None:
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError):
        return None


def _write_session(path: str, data: dict) -> None:
    """Atomic write: temp file + os.rename to prevent partial JSON."""
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
    os.rename(tmp, path)


def _now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


def _detect_gpu() -> tuple[bool, str]:
    """Detect GPU availability and type."""
    try:
        subprocess.run(["nvidia-smi"], capture_output=True, check=True)
        return True, "nvidia"
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass
    if os.path.isdir("/dev/dri"):
        return True, "igpu"
    return False, "none"


def _memory_mb() -> int:
    try:
        with open("/proc/meminfo") as f:
            for line in f:
                if line.startswith("MemTotal:"):
                    return int(line.split()[1]) // 1024
    except OSError:
        pass
    return 0


# ── Commands ──────────────────────────────────────────────────────────


def cmd_init(trigger: str) -> None:
    """Create a new telemetry session for this boot+trigger."""
    os.makedirs(TELEMETRY_DIR, exist_ok=True)
    bid = _boot_id()
    path = _session_path(bid, trigger)

    # If session already exists for this boot+trigger, keep it (append steps)
    existing = _read_session(path)
    if existing and existing.get("trigger") == trigger:
        return

    gpu_avail, gpu_type = _detect_gpu()
    data = {
        "schema_version": 1,
        "boot_id": bid,
        "arch": platform.machine(),
        "gpu_available": gpu_avail,
        "gpu_type": gpu_type,
        "memory_mb": _memory_mb(),
        "trigger": trigger,
        "timestamp_start": _now_iso(),
        "timestamp_end": None,
        "total_duration_ms": None,
        "steps": [],
        "ingested": False,
    }
    _write_session(path, data)


def _find_current_session(bid: str) -> tuple[str, dict] | tuple[None, None]:
    """Find the most recent session file for this boot_id."""
    try:
        candidates = sorted(
            Path(TELEMETRY_DIR).glob(f"{bid}-*.json"),
            key=lambda p: p.stat().st_mtime,
            reverse=True,
        )
        for c in candidates:
            session = _read_session(str(c))
            if session and session.get("boot_id") == bid:
                return str(c), session
    except OSError:
        pass
    return None, None


def cmd_record(step_name: str, command: list[str]) -> int:
    """Run a command, record its timing and result. Returns the command's exit code."""
    bid = _boot_id()
    path, session = _find_current_session(bid)
    if session is None:
        # Auto-init if no session exists
        cmd_init("unknown")
        path, session = _find_current_session(bid)

    timestamp = _now_iso()
    start = time.monotonic()

    try:
        result = subprocess.run(command, capture_output=False)
        rc = result.returncode
    except FileNotFoundError as e:
        rc = 127
        error_msg = str(e)
    else:
        error_msg = None

    elapsed_ms = int((time.monotonic() - start) * 1000)

    if rc == 0:
        status = "ok"
    else:
        status = "fail"
        if error_msg is None:
            error_msg = f"exit code {rc}"

    step = {
        "name": step_name,
        "status": status,
        "latency_ms": elapsed_ms,
        "timestamp": timestamp,
        "error": error_msg,
    }

    session["steps"].append(step)
    _write_session(path, session)

    return rc


def cmd_finalize() -> None:
    """End the session, record total duration, prune old files."""
    bid = _boot_id()
    path, session = _find_current_session(bid)
    if session is None:
        return

    session["timestamp_end"] = _now_iso()

    # Calculate total duration from start
    try:
        start = datetime.fromisoformat(session["timestamp_start"].replace("Z", "+00:00"))
        end = datetime.fromisoformat(session["timestamp_end"].replace("Z", "+00:00"))
        session["total_duration_ms"] = int((end - start).total_seconds() * 1000)
    except (ValueError, KeyError):
        pass

    _write_session(path, session)

    # Prune old files beyond MAX_FILES
    _prune_old_files()


def _prune_old_files() -> None:
    """Keep only MAX_FILES most recent telemetry files."""
    try:
        files = sorted(
            Path(TELEMETRY_DIR).glob("*.json"),
            key=lambda p: p.stat().st_mtime,
            reverse=True,
        )
        for f in files[MAX_FILES:]:
            f.unlink(missing_ok=True)
    except OSError:
        pass


def cmd_check_ingested() -> int:
    """Exit 0 if ALL of current boot's telemetry sessions are ingested, 1 otherwise."""
    bid = _boot_id()
    try:
        candidates = list(Path(TELEMETRY_DIR).glob(f"{bid}-*.json"))
    except OSError:
        return 1
    if not candidates:
        return 1
    for c in candidates:
        session = _read_session(str(c))
        if session and not session.get("ingested"):
            return 1
    return 0


def cmd_ingest() -> None:
    """Ingest all un-ingested sessions into corvia via MCP."""
    try:
        files = sorted(Path(TELEMETRY_DIR).glob("*.json"))
    except OSError:
        return

    for f in files:
        session = _read_session(str(f))
        if session is None or session.get("ingested"):
            continue

        content = _format_session_markdown(session)
        if _mcp_write(content):
            session["ingested"] = True
            session["ingested_at"] = _now_iso()
            _write_session(str(f), session)
            print(f"    setup timing saved to corvia: {f.name}")
        else:
            print(f"    failed to save setup timing: {f.name} (will retry next boot)")


def _format_session_markdown(session: dict) -> str:
    """Format a telemetry session as markdown for corvia_write."""
    ts = session.get("timestamp_start", "unknown")
    bid = session.get("boot_id", "unknown")
    trigger = session.get("trigger", "unknown")
    total_s = (session.get("total_duration_ms") or 0) / 1000
    arch = session.get("arch", "unknown")
    gpu = "yes" if session.get("gpu_available") else "no"
    gpu_type = session.get("gpu_type", "none")
    mem = session.get("memory_mb", 0)

    lines = [
        f"# Devcontainer Setup Telemetry \u2014 {ts}",
        "",
        f"**Boot ID**: {bid}",
        f"**Trigger**: {trigger}",
        f"**Total Duration**: {total_s:.1f}s",
        f"**Environment**: {arch} | GPU: {gpu} ({gpu_type}) | Memory: {mem} MB",
        "",
        "## Step Results",
        "",
        "| Step | Status | Duration |",
        "|------|--------|----------|",
    ]

    failures = []
    for step in session.get("steps", []):
        name = step.get("name", "?")
        status = step.get("status", "?")
        latency = step.get("latency_ms", 0) / 1000
        display_status = "FAIL" if status == "fail" else status
        lines.append(f"| {name} | {display_status} | {latency:.1f}s |")
        if status == "fail" and step.get("error"):
            failures.append((name, step["error"]))

    if failures:
        lines.extend(["", "## Failures", ""])
        for name, error in failures:
            lines.append(f"- **{name}**: {error}")

    return "\n".join(lines)


def _mcp_write(content: str) -> bool:
    """Write telemetry to corvia via CLI subprocess."""
    try:
        result = subprocess.run(
            ["corvia", "write", content, "--kind", "learning"],
            capture_output=True, text=True, timeout=30,
            cwd=os.environ.get("CORVIA_WORKSPACE", "/workspaces/corvia-workspace"),
        )
        return result.returncode == 0
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False


# ── CLI dispatch ──────────────────────────────────────────────────────


def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: setup_telemetry.py <init|record|finalize|ingest|check-ingested>")
        sys.exit(1)

    cmd = sys.argv[1]

    if cmd == "init":
        trigger = "post-start"
        for i, arg in enumerate(sys.argv[2:], 2):
            if arg == "--trigger" and i + 1 < len(sys.argv):
                trigger = sys.argv[i + 1]
                break
        cmd_init(trigger)

    elif cmd == "record":
        if len(sys.argv) < 3:
            print("Usage: setup_telemetry.py record <step-name> -- <command...>")
            sys.exit(1)
        step_name = sys.argv[2]
        # Find the -- separator
        try:
            sep_idx = sys.argv.index("--", 3)
            command = sys.argv[sep_idx + 1:]
        except ValueError:
            print("ERROR: missing -- separator before command", file=sys.stderr)
            sys.exit(1)
        if not command:
            print("ERROR: no command after --", file=sys.stderr)
            sys.exit(1)
        rc = cmd_record(step_name, command)
        sys.exit(rc)

    elif cmd == "finalize":
        cmd_finalize()

    elif cmd == "ingest":
        cmd_ingest()

    elif cmd == "check-ingested":
        sys.exit(cmd_check_ingested())

    else:
        print(f"Unknown command: {cmd}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
