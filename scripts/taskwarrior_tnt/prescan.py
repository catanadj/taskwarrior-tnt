"""Run an optional pre-scan helper with bounded execution."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


def command_for_script(path: Path) -> list[str]:
    try:
        with path.open(encoding="utf-8", errors="replace") as handle:
            first_line = handle.readline().strip()
    except OSError:
        return [str(path)]
    if first_line in {"#!/bin/sh", "#!/usr/bin/env sh"}:
        return ["sh", str(path)]
    if first_line in {"#!/bin/bash", "#!/usr/bin/env bash"}:
        return ["bash", str(path)]
    return [str(path)]


def run(script: str, timeout_seconds: float) -> subprocess.CompletedProcess[str]:
    path = Path(script).expanduser()
    if not path.is_file():
        raise FileNotFoundError(f"sync helper not found: {path}")
    return subprocess.run(
        command_for_script(path),
        cwd=path.parent,
        capture_output=True,
        text=True,
        check=False,
        timeout=timeout_seconds,
    )


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: prescan.py SCRIPT TIMEOUT_SECONDS", file=sys.stderr)
        return 2
    try:
        timeout_seconds = float(argv[2])
        if timeout_seconds <= 0:
            raise ValueError
    except ValueError:
        print("pre-scan timeout must be positive", file=sys.stderr)
        return 2
    try:
        result = run(argv[1], timeout_seconds)
    except FileNotFoundError as exc:
        print(str(exc), file=sys.stderr)
        return 127
    except subprocess.TimeoutExpired:
        print(f"sync helper timed out after {timeout_seconds:g}s", file=sys.stderr)
        return 124
    except OSError as exc:
        print(f"could not run sync helper: {exc}", file=sys.stderr)
        return 126
    if result.stdout:
        print(result.stdout, end="" if result.stdout.endswith("\n") else "\n")
    if result.stderr:
        print(result.stderr, end="" if result.stderr.endswith("\n") else "\n", file=sys.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
