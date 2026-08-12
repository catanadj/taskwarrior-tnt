"""Taskwarrior command adapter used by TNT Python clients."""

from __future__ import annotations

import json
import os
import subprocess
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
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [task_bin, *args],
        capture_output=True,
        text=True,
        check=False,
        env=dict(env) if env is not None else None,
    )


def export_pending(
    task_bin: str,
    now: datetime,
    future_hours: float,
    *,
    env: Mapping[str, str] | None = None,
) -> list[dict[str, object]]:
    """Export pending tasks, preferring a bounded due-date query."""
    end = now + timedelta(hours=future_hours)
    common = [
        "rc.hooks:off",
        "rc.verbose:nothing",
        "rc.json.array:on",
        "status:pending",
    ]
    result = _run_export(
        task_bin,
        [*common, f"due.before:{end.strftime('%Y%m%dT%H%M%S')}", "export"],
        env,
    )
    if result.returncode != 0:
        result = _run_export(task_bin, [*common, "export"], env)
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
    return [item for item in payload if isinstance(item, dict)]


def normalize_task(item: Mapping[str, object]) -> TaskRecord | None:
    """Convert one raw Taskwarrior export object into a typed task record."""
    uuid = clean_text(item.get("uuid"))
    due = parse_task_date(clean_text(item.get("due")))
    if not uuid or due is None:
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
        started=bool(item.get("start")),
    )


def normalize_tasks(items: list[Mapping[str, object]]) -> list[TaskRecord]:
    return [record for item in items if (record := normalize_task(item)) is not None]
