"""Snooze deadline calculation."""

from __future__ import annotations

import os
import sys
from datetime import datetime, timedelta


def until_epoch(value: str, now: datetime | None = None) -> int:
    value = value.strip().lower()
    now = now or (datetime.fromisoformat(os.environ["TW_TEST_NOW"]) if os.environ.get("TW_TEST_NOW") else datetime.now().astimezone())
    if now.tzinfo is None:
        now = now.astimezone()
    if value in ("tomorrow", "+1 day", "1 day"):
        target = now + timedelta(days=1)
    elif value in ("+1 hour", "1 hour", "1h"):
        target = now + timedelta(hours=1)
    elif value.endswith("h") and value[:-1].replace(".", "", 1).isdigit():
        target = now + timedelta(hours=float(value[:-1]))
    elif value.endswith("m") and value[:-1].replace(".", "", 1).isdigit():
        target = now + timedelta(minutes=float(value[:-1]))
    else:
        raise ValueError(f"unsupported snooze value: {value}")
    return int(target.timestamp())


if __name__ == "__main__":
    try:
        print(until_epoch(sys.argv[1]))
    except (IndexError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(2)
