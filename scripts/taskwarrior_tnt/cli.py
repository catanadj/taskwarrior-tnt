"""Unified command-line entry point for Taskwarrior TNT."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path


def scripts_dir() -> Path:
    return Path(__file__).resolve().parent.parent


def run_script(name: str, *args: str) -> int:
    result = subprocess.run(["bash", str(scripts_dir() / name), *args], check=False)
    return result.returncode


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="tnt", description="Taskwarrior TNT command line")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("scan", help="scan and update notifications")
    doctor = sub.add_parser("doctor", help="run installation diagnostics")
    doctor.set_defaults(args=("--doctor",))
    channels = sub.add_parser("channels", help="manage Android notification channels")
    channels.add_argument("action", choices=("setup",))
    action = sub.add_parser("action", help="run a task action")
    action.add_argument("name", choices=("start", "stop", "done", "snooze"))
    action.add_argument("uuid")
    action.add_argument("notification_id", nargs="?")
    action.add_argument("snooze_value", nargs="?")
    sub.add_parser("gui", help="open the Termux:GUI dashboard")
    sub.add_parser("status", help="show notification state")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.command == "scan":
        return run_script("taskwarrior_notify_due_tasks.sh")
    if args.command == "doctor":
        return run_script("taskwarrior_notify_due_tasks.sh", "--doctor")
    if args.command == "channels":
        return run_script("taskwarrior_notify_due_tasks.sh", "--setup-channels")
    if args.command == "gui":
        return run_script("taskwarrior_gui.sh")
    if args.command == "status":
        return run_script("taskwarrior_notify_due_tasks.sh", "--doctor")
    script = {
        "start": "taskwarrior_start_stop_task.sh",
        "stop": "taskwarrior_start_stop_task.sh",
        "done": "taskwarrior_complete_task.sh",
        "snooze": "taskwarrior_snooze_task.sh",
    }[args.name]
    if args.name == "snooze":
        return run_script(script, args.uuid, args.notification_id or "", args.snooze_value or "tomorrow")
    if args.name in {"start", "stop"}:
        return run_script(script, args.name, args.uuid, args.notification_id or "")
    return run_script(script, args.uuid, args.notification_id or "")


if __name__ == "__main__":
    raise SystemExit(main())
