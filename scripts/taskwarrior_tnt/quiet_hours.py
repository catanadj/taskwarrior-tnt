"""Quiet-hours boundary calculation."""

from __future__ import annotations

import os
import re
import sys
from datetime import datetime


def is_quiet(enabled: str, start_value: str, end_value: str, now: datetime | None = None) -> bool:
    if enabled != "1":
        return False
    pattern = re.compile(r"^([01]\d|2[0-3]):([0-5]\d)$")
    start_match = pattern.match(start_value)
    end_match = pattern.match(end_value)
    if not start_match or not end_match:
        raise ValueError(f"invalid quiet hours: {start_value}-{end_value}")
    start = int(start_match.group(1)) * 60 + int(start_match.group(2))
    end = int(end_match.group(1)) * 60 + int(end_match.group(2))
    now = now or (datetime.fromisoformat(os.environ["TW_TEST_NOW"]) if os.environ.get("TW_TEST_NOW") else datetime.now().astimezone())
    minute = now.hour * 60 + now.minute
    if start == end:
        return False
    if start < end:
        return start <= minute < end
    return minute >= start or minute < end


if __name__ == "__main__":
    try:
        raise SystemExit(0 if is_quiet(*sys.argv[1:4]) else 1)
    except (IndexError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(2)
