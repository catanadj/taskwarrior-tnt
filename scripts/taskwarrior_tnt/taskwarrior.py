"""Taskwarrior command adapter used by TNT Python clients."""

from __future__ import annotations

import json
import os
import shlex
import subprocess
import sys
from datetime import datetime, timedelta
from typing import Mapping

from taskwarrior_tnt.formatting import clean_text, parse_iso_duration, parse_task_date
from taskwarrior_tnt.models import TaskRecord


class TaskwarriorCommandError(RuntimeError):
    """Raised when Taskwarrior cannot produce a usable export."""


def _run_export(
    task_bin: str,
    args: list[str],
    env: Mapping[str, str] | None,
    timeout_seconds: float | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [task_bin, *args],
        capture_output=True,
        text=True,
        check=False,
        env=dict(env) if env is not None else None,
        timeout=timeout_seconds,
    )


def export_pending(
    task_bin: str,
    now: datetime,
    future_hours: float,
    *,
    env: Mapping[str, str] | None = None,
    task_filter: str = "",
    timeout_seconds: float = 30,
) -> list[dict[str, object]]:
    """Export pending tasks, preferring a bounded due-date query."""
    end = now + timedelta(hours=future_hours)
    common = [
        "rc.hooks:off",
        "rc.verbose:nothing",
        "rc.json.array:on",
        "status:pending",
    ]
    filter_args = shlex.split(task_filter) if task_filter.strip() else []
    try:
        result = _run_export(
            task_bin,
            [*common, *filter_args, f"due.before:{end.strftime('%Y%m%dT%H%M%S')}", "export"],
            env,
            timeout_seconds,
        )
    except subprocess.TimeoutExpired as exc:
        raise TaskwarriorCommandError(f"task export timed out after {timeout_seconds:g}s") from exc
    if result.returncode != 0:
        result = _run_export(task_bin, [*common, *filter_args, "export"], env, timeout_seconds)
    if result.returncode != 0:
        message = " ".join((result.stderr or result.stdout or "").split())
        raise TaskwarriorCommandError(message or "task export failed")
    try:
        payload = json.loads(result.stdout or "[]")
    except json.JSONDecodeError as exc:
        raise TaskwarriorCommandError(
            f"task export did not return valid JSON: {exc}"
        ) from exc
    if not isinstance(payload, list):
        raise TaskwarriorCommandError("task export did not return a JSON array")

    # A due-date query omits active tasks without a due date. Fetch those
    # separately so an active task remains visible and actionable.
    try:
        active_result = _run_export(
            task_bin, [*common, *filter_args, "start.any", "export"], env, timeout_seconds
        )
    except subprocess.TimeoutExpired:
        active_result = subprocess.CompletedProcess([], 124, "", "")
    if active_result.returncode == 0:
        try:
            active_payload = json.loads(active_result.stdout or "[]")
        except json.JSONDecodeError:
            active_payload = []
        if isinstance(active_payload, list):
            payload.extend(item for item in active_payload if isinstance(item, dict))

    unique: dict[str, dict[str, object]] = {}
    for item in payload:
        if isinstance(item, dict):
            key = str(item.get("uuid") or len(unique))
            unique[key] = item
    return list(unique.values())


def normalize_task(item: Mapping[str, object]) -> TaskRecord | None:
    """Convert one raw Taskwarrior export object into a typed task record."""
    uuid = clean_text(item.get("uuid"))
    started = bool(item.get("start"))
    started_at = parse_task_date(clean_text(item.get("start"))) if started else None
    due = parse_task_date(clean_text(item.get("due")))
    if not uuid or (due is None and not started):
        return None
    raw_tags = item.get("tags") or ()
    tags = tuple(clean_text(tag) for tag in raw_tags if clean_text(tag)) if isinstance(raw_tags, (list, tuple)) else ()
    try:
        urgency = float(item.get("urgency") or 0)
    except (TypeError, ValueError):
        urgency = 0.0
    return TaskRecord(
        uuid=uuid,
        due=due,
        description=clean_text(item.get("description")),
        project=clean_text(item.get("project")),
        tags=tags,
        duration=parse_iso_duration(clean_text(item.get("duration"))),
        urgency=urgency,
        started=started,
        started_at=started_at,
    )


def normalize_tasks(items: list[Mapping[str, object]]) -> list[TaskRecord]:
    return [record for item in items if (record := normalize_task(item)) is not None]


def snapshot(task_bin: str, uuid: str) -> tuple[str, str, str, str, str, str]:
    """Return status, start epoch, and optional Nautical recurrence fields."""
    result = subprocess.run(
        [task_bin, "rc.hooks:off", "rc.verbose:nothing", "rc.json.array:on", uuid, "export"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise TaskwarriorCommandError(result.stderr.strip() or result.stdout.strip() or "task snapshot failed")
    try:
        tasks = json.loads(result.stdout or "[]")
    except json.JSONDecodeError as exc:
        raise TaskwarriorCommandError(f"invalid Taskwarrior JSON: {exc}") from exc
    task = next((item for item in tasks if item.get("uuid") == uuid), None)
    if task is None:
        return "missing", "", "", "", "", ""
    started = ""
    value = task.get("start")
    if value:
        for fmt in ("%Y%m%dT%H%M%SZ", "%Y%m%dT%H%M%S"):
            try:
                parsed = datetime.strptime(value, fmt)
            except ValueError:
                continue
            if value.endswith("Z"):
                from datetime import timezone
                parsed = parsed.replace(tzinfo=timezone.utc).astimezone()
            else:
                parsed = parsed.astimezone()
            started = str(int(parsed.timestamp()))
            break
    return (
        str(task.get("status") or "unknown"),
        started,
        str(task.get("chainID") or ""),
        str(task.get("link") or ""),
        str(task.get("chainMax") or ""),
        str(task.get("anchor") or task.get("cp") or ""),
    )


if __name__ == "__main__" and len(sys.argv) == 4 and sys.argv[1] == "snapshot":
    try:
        status, started, chain_id, link, chain_max, recurrence = snapshot(sys.argv[2], sys.argv[3])
        print(f"{status}|{started}|{chain_id}|{link}|{chain_max}|{recurrence}")
    except TaskwarriorCommandError as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(2)
