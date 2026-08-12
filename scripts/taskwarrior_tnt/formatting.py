"""Date, duration, and text formatting shared by TNT Python clients."""

from __future__ import annotations

import re
import time
from datetime import datetime, timedelta, timezone
from typing import Any


def parse_task_date(value: str | None) -> datetime | None:
    if not value:
        return None
    for fmt in ("%Y%m%dT%H%M%SZ", "%Y%m%dT%H%M%S"):
        try:
            parsed = datetime.strptime(value, fmt)
            if value.endswith("Z"):
                return parsed.replace(tzinfo=timezone.utc).astimezone()
            return parsed.astimezone()
        except ValueError:
            pass
    return None


def parse_iso_duration(value: str | None) -> timedelta | None:
    if not value:
        return None
    match = re.fullmatch(
        r"P(?:(?P<days>\d+(?:\.\d+)?)D)?"
        r"(?:T(?:(?P<hours>\d+(?:\.\d+)?)H)?"
        r"(?:(?P<minutes>\d+(?:\.\d+)?)M)?"
        r"(?:(?P<seconds>\d+(?:\.\d+)?)S)?)?",
        str(value).strip(),
    )
    if not match:
        return None
    parts = {key: float(item or 0) for key, item in match.groupdict().items()}
    duration = timedelta(
        days=parts["days"],
        hours=parts["hours"],
        minutes=parts["minutes"],
        seconds=parts["seconds"],
    )
    return duration if duration.total_seconds() > 0 else None


def clean_text(value: Any) -> str:
    return " ".join(str(value or "").split())


def format_delta(delta: timedelta) -> str:
    total_seconds = int(abs(delta.total_seconds()))
    minutes = max(1, (total_seconds + 59) // 60)
    hours, remaining_minutes = divmod(minutes, 60)
    days, remaining_hours = divmod(hours, 24)
    parts = []
    if days:
        parts.append(f"{days}d")
    if remaining_hours:
        parts.append(f"{remaining_hours}h")
    if remaining_minutes and not days:
        parts.append(f"{remaining_minutes}m")
    return " ".join(parts) if parts else "0m"


def format_elapsed(start_epoch: int, now_epoch: int | None = None) -> str:
    seconds = max(0, int(time.time() if now_epoch is None else now_epoch) - int(start_epoch))
    minutes = max(1, (seconds + 59) // 60)
    hours, remaining_minutes = divmod(minutes, 60)
    days, remaining_hours = divmod(hours, 24)
    parts = []
    if days:
        parts.append(f"{days}d")
    if remaining_hours:
        parts.append(f"{remaining_hours}h")
    if remaining_minutes and not days:
        parts.append(f"{remaining_minutes}m")
    return " ".join(parts) if parts else "0m"


if __name__ == "__main__":
    import sys

    if len(sys.argv) not in (2, 3):
        raise SystemExit(2)
    print(format_elapsed(int(sys.argv[1]), int(sys.argv[2]) if len(sys.argv) == 3 else None))
