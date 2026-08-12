"""Shared reminder eligibility and priority policy."""

from __future__ import annotations

from collections.abc import Callable, Iterable
from datetime import datetime, timedelta
from typing import TypeVar


Record = TypeVar("Record")


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
