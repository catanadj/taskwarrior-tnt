"""Unified command-line entry point for Taskwarrior TNT."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

from taskwarrior_tnt.config import migrate_to_toml, read_config, validate
from taskwarrior_tnt.policy import filter_tasks
from taskwarrior_tnt.reminders import build_reminders
from taskwarrior_tnt.state import migrate_to_json, read_manifest, read_snoozes
from taskwarrior_tnt.taskwarrior import TaskwarriorCommandError, export_pending, normalize_tasks

VERSION = "0.2.0"


def scripts_dir() -> Path:
    return Path(__file__).resolve().parent.parent


def run_script(name: str, *args: str) -> int:
    result = subprocess.run(["bash", str(scripts_dir() / name), *args], check=False)
    return result.returncode


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="tnt", description="Taskwarrior TNT command line")
    parser.add_argument("--version", action="version", version=VERSION)
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
    config = sub.add_parser("config", help="validate configuration")
    config.add_argument("action", choices=("check", "migrate"))
    state = sub.add_parser("state", help="manage state files")
    state.add_argument("action", choices=("migrate",))
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
        state_dir = Path(os.environ.get("TW_STATE_DIR", "~/.local/state/taskwarrior-tnt")).expanduser()
        now_epoch = int(time.time())
        print(f"version={VERSION}")
        print(f"state_dir={state_dir}")
        print(f"active_notifications={len(read_manifest(state_dir / 'active-notifications'))}")
        print(f"snoozed_tasks={len(read_snoozes(state_dir / 'snoozed-tasks', now_epoch))}")
        channel_state = state_dir / "notification-channels"
        print(f"channels_cached={'yes' if channel_state.exists() else 'no'}")
        values: dict[str, str]
        try:
            values = read_config()
        except ValueError:
            values = {}
        try:
            now = datetime.now().astimezone()
            tasks = normalize_tasks(
                export_pending(
                    values.get("TASK_BIN", "task"),
                    now,
                    float(values.get("TW_WINDOW_FUTURE_HOURS", "2")),
                    task_filter=values.get("TW_TASK_FILTER", ""),
                    timeout_seconds=float(values.get("TW_COMMAND_TIMEOUT_SECONDS", "30")),
                )
            )
            tasks = filter_tasks(
                tasks,
                include_projects=values.get("TW_INCLUDE_PROJECTS", ""),
                exclude_projects=values.get("TW_EXCLUDE_PROJECTS", ""),
                include_tags=values.get("TW_INCLUDE_TAGS", ""),
                exclude_tags=values.get("TW_EXCLUDE_TAGS", ""),
                opt_out_tag=values.get("TW_OPTOUT_TAG", ""),
            )
            reminders = build_reminders(
                tasks,
                now,
                float(values.get("TW_WINDOW_PAST_HOURS", "2")),
                float(values.get("TW_WINDOW_FUTURE_HOURS", "2")),
                int(values.get("TW_MAX_TASKS", "12")),
                set(read_snoozes(state_dir / "snoozed-tasks", now_epoch)),
                values.get("TW_ALWAYS_SHOW_ACTIVE", "0") == "1",
            )
            if reminders:
                print(f"next_reminder={reminders[0].title}")
                print(f"next_bucket={reminders[0].bucket}")
            else:
                print("next_reminder=none")
        except (TaskwarriorCommandError, ValueError, OSError) as exc:
            print(f"next_reminder=unavailable ({exc})")
        return 0
    if args.command == "config":
        if args.action == "migrate":
            try:
                print(f"Wrote {migrate_to_toml()}")
            except ValueError as exc:
                print(f"ERROR: {exc}", file=sys.stderr)
                return 2
            return 0
        try:
            errors = validate(read_config())
        except ValueError as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            return 2
        if errors:
            for error in errors:
                print(f"ERROR: {error}", file=sys.stderr)
            return 2
        print("Configuration is valid.")
        return 0
    if args.command == "state" and args.action == "migrate":
        state_dir = os.environ.get("TW_STATE_DIR", "~/.local/state/taskwarrior-tnt")
        print(f"Wrote {migrate_to_json(Path(state_dir).expanduser())}")
        return 0
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
