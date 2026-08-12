#!/usr/bin/env python3
"""On-demand Termux:GUI dashboard for Taskwarrior reminder actions."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

from taskwarrior_tnt.formatting import (
    clean_text,
    format_delta,
    parse_iso_duration,
    parse_task_date,
)
from taskwarrior_tnt.reminders import build_reminders
from taskwarrior_tnt.policy import filter_tasks
from taskwarrior_tnt.models import Reminder as TaskRow
from taskwarrior_tnt.taskwarrior import (
    TaskwarriorCommandError,
    export_pending,
    normalize_tasks,
)
from taskwarrior_tnt.state import read_snoozes

try:
    import termuxgui as tg
except ModuleNotFoundError:
    sys.exit(
        "termuxgui module not found. Install Termux:GUI and run: pip install termuxgui"
    )


DEFAULT_CONFIG = os.path.expanduser("~/.termux/tasker/taskwarrior_tasker.conf")


@dataclass
class Config:
    task_bin: str = "task"
    task_filter: str = ""
    command_timeout_seconds: float = 30
    include_projects: str = ""
    exclude_projects: str = ""
    include_tags: str = ""
    exclude_tags: str = ""
    opt_out_tag: str = ""
    past_hours: float = 2
    future_hours: float = 2
    max_tasks: int = 12
    state_dir: str = os.path.expanduser(
        "~/.local/state/taskwarrior-tnt"
    )
    start_stop_script: str = os.path.expanduser(
        "~/.termux/tasker/taskwarrior_start_stop_task.sh"
    )
    complete_script: str = os.path.expanduser(
        "~/.termux/tasker/taskwarrior_complete_task.sh"
    )
    snooze_script: str = os.path.expanduser(
        "~/.termux/tasker/taskwarrior_snooze_task.sh"
    )
    notify_script: str = os.path.expanduser(
        "~/.termux/tasker/taskwarrior_notify_due_tasks.sh"
    )
    action_log_file: str = os.path.expanduser(
        "~/.local/state/taskwarrior-tnt/action.log"
    )
    gui_cache_file: str = os.path.expanduser(
        "~/.local/state/taskwarrior-tnt/gui-cache.json"
    )
    gui_cache_max_age_seconds: int = 900
    always_show_active: bool = False


def load_config(path: str) -> Config:
    if not os.path.exists(path):
        return Config()

    command = 'set -a; source "$1"; env'
    result = subprocess.run(
        ["bash", "-c", command, "taskwarrior-gui-config", path],
        capture_output=True,
        text=True,
        check=False,
    )
    values: dict[str, str] = {}
    if result.returncode == 0:
        for line in result.stdout.splitlines():
            key, _, value = line.partition("=")
            values[key] = value

    def num(name: str, default: float) -> float:
        try:
            return float(values.get(name, default))
        except (TypeError, ValueError):
            return default

    def integer(name: str, default: int) -> int:
        try:
            return int(values.get(name, default))
        except (TypeError, ValueError):
            return default

    state_dir = values.get(
        "TW_STATE_DIR", os.path.expanduser("~/.local/state/taskwarrior-tnt")
    )
    return Config(
        task_bin=values.get("TASK_BIN", "task"),
        task_filter=values.get("TW_TASK_FILTER", ""),
        command_timeout_seconds=num("TW_COMMAND_TIMEOUT_SECONDS", 30),
        include_projects=values.get("TW_INCLUDE_PROJECTS", ""),
        exclude_projects=values.get("TW_EXCLUDE_PROJECTS", ""),
        include_tags=values.get("TW_INCLUDE_TAGS", ""),
        exclude_tags=values.get("TW_EXCLUDE_TAGS", ""),
        opt_out_tag=values.get("TW_OPTOUT_TAG", ""),
        past_hours=num("TW_WINDOW_PAST_HOURS", 2),
        future_hours=num("TW_WINDOW_FUTURE_HOURS", 2),
        max_tasks=integer("TW_MAX_TASKS", 12),
        state_dir=state_dir,
        start_stop_script=values.get(
            "TW_START_STOP_SCRIPT",
            os.path.expanduser("~/.termux/tasker/taskwarrior_start_stop_task.sh"),
        ),
        complete_script=values.get(
            "TW_COMPLETE_SCRIPT",
            os.path.expanduser("~/.termux/tasker/taskwarrior_complete_task.sh"),
        ),
        snooze_script=values.get(
            "TW_SNOOZE_SCRIPT",
            os.path.expanduser("~/.termux/tasker/taskwarrior_snooze_task.sh"),
        ),
        notify_script=values.get(
            "TW_NOTIFY_SCRIPT",
            os.path.expanduser("~/.termux/tasker/taskwarrior_notify_due_tasks.sh"),
        ),
        action_log_file=values.get(
            "TW_ACTION_LOG_FILE", os.path.join(state_dir, "action.log")
        ),
        gui_cache_file=values.get(
            "TW_GUI_CACHE_FILE", os.path.join(state_dir, "gui-cache.json")
        ),
        gui_cache_max_age_seconds=integer("TW_GUI_CACHE_MAX_AGE_SECONDS", 900),
        always_show_active=values.get("TW_ALWAYS_SHOW_ACTIVE", "0") == "1",
    )


def read_snoozed(state_dir: str) -> set[str]:
    path = Path(state_dir) / "snoozed-tasks"
    now_epoch = int(datetime.now().astimezone().timestamp())
    return set(read_snoozes(path, now_epoch))


def taskrow_from_cache(item: dict[str, Any]) -> TaskRow | None:
    due = parse_task_date(clean_text(item.get("due")))
    if due is None:
        return None
    uuid = clean_text(item.get("uuid"))
    title = clean_text(item.get("title"))
    if not uuid or not title:
        return None
    return TaskRow(
        bucket=clean_text(item.get("bucket")) or "window",
        uuid=uuid,
        title=title,
        content=clean_text(item.get("content")),
        action=clean_text(item.get("action")) or "start",
        button=clean_text(item.get("button")) or "Start",
        due=due,
        urgency=float(item.get("urgency") or 0),
    )


def read_task_cache(config: Config) -> list[TaskRow] | None:
    if os.environ.get("TW_GUI_BYPASS_CACHE") == "1":
        return None
    if config.gui_cache_max_age_seconds <= 0:
        return None

    path = Path(config.gui_cache_file)
    try:
        payload = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return None

    generated_epoch = int(payload.get("generated_epoch") or 0)
    now_epoch = int(datetime.now().astimezone().timestamp())
    if now_epoch - generated_epoch > config.gui_cache_max_age_seconds:
        return None

    rows = []
    for item in payload.get("tasks") or []:
        row = taskrow_from_cache(item)
        if row is not None:
            rows.append(row)
    return rows


def write_task_cache(config: Config, rows: list[TaskRow]) -> None:
    payload = {
        "generated_epoch": int(datetime.now().astimezone().timestamp()),
        "tasks": [
            {
                "bucket": row.bucket,
                "uuid": row.uuid,
                "title": row.title,
                "content": row.content,
                "action": row.action,
                "button": row.button,
                "due": row.due.strftime("%Y%m%dT%H%M%S"),
                "urgency": row.urgency,
            }
            for row in rows
        ],
    }
    try:
        path = Path(config.gui_cache_file)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(payload, separators=(",", ":")))
    except OSError:
        pass


def load_tasks(config: Config) -> tuple[list[TaskRow], str]:
    cached_rows = read_task_cache(config)
    if cached_rows is not None:
        return cached_rows, f"{len(cached_rows)} task(s) from cache"

    now = datetime.now().astimezone()
    try:
        tasks = filter_tasks(
            normalize_tasks(
                export_pending(
                config.task_bin,
                now,
                config.future_hours,
                task_filter=config.task_filter,
                timeout_seconds=config.command_timeout_seconds,
                )
            ),
            include_projects=config.include_projects,
            exclude_projects=config.exclude_projects,
            include_tags=config.include_tags,
            exclude_tags=config.exclude_tags,
            opt_out_tag=config.opt_out_tag,
        )
    except TaskwarriorCommandError as exc:
        return [], str(exc)

    snoozed = read_snoozed(config.state_dir)

    rows = build_reminders(
        tasks,
        now,
        config.past_hours,
        config.future_hours,
        config.max_tasks,
        snoozed,
        config.always_show_active,
    )
    write_task_cache(config, rows)
    return rows, ""


def run_action(args: list[str]) -> str:
    result = subprocess.run(args, capture_output=True, text=True, check=False)
    output = clean_text(result.stdout or result.stderr)
    if result.returncode == 0:
        return output or "OK"
    return f"failed ({result.returncode}): {output}"


def tail_file(path: str, lines: int = 12) -> str:
    try:
        content = Path(path).read_text().splitlines()
    except OSError as exc:
        return f"Cannot read log: {exc}"
    return "\n".join(content[-lines:]) if content else "Log is empty."


def restart(bypass_cache: bool = False) -> None:
    if bypass_cache:
        os.environ["TW_GUI_BYPASS_CACHE"] = "1"
    os.execv(sys.executable, [sys.executable, *sys.argv])


def add_header(tg_module: Any, activity: Any, layout: Any, text: str) -> None:
    tv = tg_module.TextView(activity, text, layout)
    tv.settextsize(20)
    tv.setmargin(4)
    tv.setheight(tg_module.View.WRAP_CONTENT)
    tv.setlinearlayoutparams(0)


def add_spacer(tg_module: Any, activity: Any, layout: Any) -> None:
    spacer = tg_module.TextView(activity, " ", layout)
    spacer.settextsize(4)
    spacer.setheight(tg_module.View.WRAP_CONTENT)
    spacer.setlinearlayoutparams(0)


def task_marker(task: TaskRow) -> str:
    if task.action == "stop":
        return "*"
    if task.bucket == "overdue":
        return "!"
    return "-"


def clip_text(value: str, max_length: int = 96) -> str:
    return value if len(value) <= max_length else f"{value[: max_length - 3]}..."


def compact_task_text(task: TaskRow) -> str:
    detail = task.content.split(" | ", 2)
    suffix = " | ".join(detail[:2])
    return clip_text(f"  {task_marker(task)} {task.title} | {suffix}")


def add_task(
    tg_module: Any,
    activity: Any,
    layout: Any,
    task: TaskRow,
    task_clicks: list[tuple[Any, TaskRow]],
    row_titles: dict[str, tuple[Any, str]],
) -> None:
    title_text = compact_task_text(task)
    title = tg_module.TextView(activity, title_text, layout)
    title.settextsize(16)
    title.setmargin(4)
    title.setheight(tg_module.View.WRAP_CONTENT)
    title.setlinearlayoutparams(0)
    title.sendclickevent(True)

    add_spacer(tg_module, activity, layout)
    task_clicks.append((title, task))
    row_titles[task.uuid] = (title, title_text)


def main() -> None:
    config_path = os.environ.get("TW_CONFIG_FILE", DEFAULT_CONFIG)
    config = load_config(config_path)
    tasks, error = load_tasks(config)

    with tg.Connection() as connection:
        activity = tg.Activity(connection)
        root = tg.LinearLayout(activity)
        task_clicks: list[tuple[Any, TaskRow]] = []
        row_titles: dict[str, tuple[Any, str]] = {}
        selected_task: TaskRow | None = None

        overdue = [task for task in tasks if task.bucket == "overdue"]
        window = [task for task in tasks if task.bucket == "window"]

        title = tg.TextView(
            activity,
            f"Taskwarrior TNT | {len(overdue)} overdue | {len(window)} window",
            root,
        )
        title.settextsize(24)
        title.setheight(tg.View.WRAP_CONTENT)
        title.setlinearlayoutparams(0)

        toolbar = tg.LinearLayout(activity, root, False)
        toolbar.setheight(tg.View.WRAP_CONTENT)
        toolbar.setlinearlayoutparams(0)
        refresh = tg.Button(activity, "Refresh", toolbar)
        doctor = tg.Button(activity, "Doctor", toolbar)
        logs = tg.Button(activity, "Logs", toolbar)
        close = tg.Button(activity, "Close", toolbar)

        status = tg.TextView(activity, error or f"{len(tasks)} task(s)", root)
        status.setheight(tg.View.WRAP_CONTENT)
        status.setlinearlayoutparams(0)

        selected_title = tg.TextView(activity, "Selected: none", root)
        selected_title.settextsize(18)
        selected_title.setmargin(4)
        selected_title.setheight(tg.View.WRAP_CONTENT)
        selected_title.setlinearlayoutparams(0)

        selected_details = tg.TextView(activity, "Tap a task to choose actions.", root)
        selected_details.settextsize(13)
        selected_details.setmargin(2)
        selected_details.setheight(tg.View.WRAP_CONTENT)
        selected_details.setlinearlayoutparams(0)

        action_bar = tg.LinearLayout(activity, root, False)
        action_bar.setheight(tg.View.WRAP_CONTENT)
        action_bar.setlinearlayoutparams(0)
        start_stop = tg.Button(activity, "Start/Stop", action_bar)
        done = tg.Button(activity, "Done", action_bar)
        tomorrow = tg.Button(activity, "Tomorrow", action_bar)
        snooze = tg.Button(activity, "Snooze", action_bar)

        def select_task(task: TaskRow) -> None:
            nonlocal selected_task
            selected_task = task
            for task_uuid, (title_view, original_text) in row_titles.items():
                title_view.settext(
                    f"> {original_text[2:]}" if task_uuid == task.uuid else original_text
                )
            start_stop.settext(task.button)
            selected_title.settext(f"Selected: {task.title}")
            selected_details.settext(task.content)

        def selected_command(button: Any) -> list[str] | None:
            if selected_task is None:
                connection.toast("Select a task first", True)
                return None
            if button == start_stop:
                return [
                    config.start_stop_script,
                    selected_task.action,
                    selected_task.uuid,
                ]
            if button == done:
                return [config.complete_script, selected_task.uuid]
            if button == tomorrow:
                return [config.snooze_script, selected_task.uuid, "", "tomorrow"]
            if button == snooze:
                return [config.snooze_script, selected_task.uuid, "", "1h"]
            return None

        add_header(tg, activity, root, f"Today Overdue ({len(overdue)})")
        if overdue:
            for task in overdue:
                add_task(tg, activity, root, task, task_clicks, row_titles)
        else:
            empty = tg.TextView(activity, "None", root)
            empty.setheight(tg.View.WRAP_CONTENT)
            empty.setlinearlayoutparams(0)

        add_header(tg, activity, root, f"Execution Window ({len(window)})")
        if window:
            for task in window:
                add_task(tg, activity, root, task, task_clicks, row_titles)
        else:
            empty = tg.TextView(activity, "None", root)
            empty.setheight(tg.View.WRAP_CONTENT)
            empty.setlinearlayoutparams(0)

        if tasks:
            select_task(tasks[0])

        for event in connection.events():
            if event.type == tg.Event.destroy and event.value.get("finishing"):
                return
            if event.type != tg.Event.click:
                continue

            clicked = event.value.get("id")
            if clicked == close:
                activity.finish()
                return
            if clicked == refresh:
                restart(bypass_cache=True)
            if clicked == doctor:
                output = run_action([config.notify_script, "--doctor"])
                status.settext(output[-1800:])
                continue
            if clicked == logs:
                status.settext(tail_file(config.action_log_file))
                continue

            for task_view, task in task_clicks:
                if clicked == task_view:
                    select_task(task)
                    break
            else:
                command = selected_command(clicked)
                if command is not None:
                    result = run_action(command)
                    connection.toast(result[:120], True)
                    restart(bypass_cache=True)


if __name__ == "__main__":
    main()
