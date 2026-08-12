"""Shared reminder eligibility and priority policy."""

from __future__ import annotations

from collections.abc import Callable, Iterable
from datetime import datetime, timedelta
from typing import TypeVar

from taskwarrior_tnt.models import TaskRecord


Record = TypeVar("Record")


def _csv(value: str) -> set[str]:
    return {item.strip() for item in value.split(",") if item.strip()}


def filter_tasks(
    tasks: Iterable["TaskRecord"],
    *,
    include_projects: str = "",
    exclude_projects: str = "",
    include_tags: str = "",
    exclude_tags: str = "",
    opt_out_tag: str = "",
) -> list["TaskRecord"]:
    """Apply optional project and tag eligibility rules consistently."""
    included_projects = _csv(include_projects)
    excluded_projects = _csv(exclude_projects)
    included_tags = _csv(include_tags)
    excluded_tags = _csv(exclude_tags)
    return [
        task
        for task in tasks
        if (not included_projects or task.project in included_projects)
        and task.project not in excluded_projects
        and (not included_tags or included_tags.intersection(task.tags))
        and not excluded_tags.intersection(task.tags)
        and (not opt_out_tag.strip() or opt_out_tag.strip() not in task.tags)
    ]


def reminder_bucket(
    due: datetime,
    now: datetime,
    past_hours: float,
    future_hours: float,
) -> str | None:
    """Return the reminder bucket for a due date, or None if it is ineligible."""
    start = now - timedelta(hours=past_hours)
    end = now + timedelta(hours=future_hours)
    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    if due < today_start or due > end:
        return None
    return "overdue" if due < start else "window"


def select_priority(
    records: Iterable[Record],
    max_records: int,
    *,
    due_key: Callable[[Record], datetime],
    urgency_key: Callable[[Record], float],
    bucket_key: Callable[[Record], str],
    active_key: Callable[[Record], bool],
) -> list[Record]:
    """Sort and limit active, window, and overdue reminders consistently."""
    ordered = sorted(records, key=lambda item: (due_key(item), -urgency_key(item)))
    active = [item for item in ordered if active_key(item)]
    window = [
        item
        for item in ordered
        if bucket_key(item) == "window" and not active_key(item)
    ]
    overdue = [
        item
        for item in ordered
        if bucket_key(item) == "overdue" and not active_key(item)
    ]
    selected = {id(item) for item in (active + window + overdue)[:max_records]}
    return [item for item in ordered if id(item) in selected]
