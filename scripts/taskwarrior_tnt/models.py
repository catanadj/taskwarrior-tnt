"""Typed domain models shared by TNT Python clients."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta


@dataclass(frozen=True)
class TaskRecord:
    """Normalized fields used from a Taskwarrior export record."""

    uuid: str
    due: datetime | None
    description: str = ""
    project: str = ""
    tags: tuple[str, ...] = ()
    duration: timedelta | None = None
    urgency: float = 0.0
    started: bool = False
    started_at: datetime | None = None


@dataclass(frozen=True)
class Reminder:
    """A rendered task reminder ready for a GUI or notification client."""

    bucket: str
    uuid: str
    title: str
    content: str
    action: str
    button: str
    due: datetime
    urgency: float = 0.0
