"""Optional Nautical daily occurrence progress for timed anchor tasks."""

from __future__ import annotations

import importlib
import json
import os
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, time
from pathlib import Path
from typing import Any, Iterable, Mapping

from taskwarrior_tnt.formatting import parse_task_date


@dataclass(frozen=True)
class DailyProgress:
    position: int
    total: int

    @property
    def remaining(self) -> int:
        return self.total - self.position


def progress_from_occurrences(
    due: datetime, occurrences: Iterable[datetime]
) -> DailyProgress | None:
    ordered = sorted(set(occurrences))
    for index, occurrence in enumerate(ordered, 1):
        if abs((occurrence - due).total_seconds()) < 60:
            return DailyProgress(index, len(ordered))
    return None


def _load_nautical_scheduler() -> tuple[Any, Any, Any] | None:
    candidates = []
    for value in (
        os.environ.get("NAUTICAL_CORE_PATH"),
        os.environ.get("TASKDATA"),
        Path(os.environ["TASKRC"]).expanduser().parent if os.environ.get("TASKRC") else None,
        Path.home() / ".task",
    ):
        if value:
            candidates.append(Path(value).expanduser())
    for candidate in candidates:
        base = candidate.parent if candidate.name == "nautical_core" else candidate
        if (base / "nautical_core" / "__init__.py").is_file():
            path = str(base)
            if path not in sys.path:
                sys.path.insert(0, path)
            break
    try:
        service = importlib.import_module("nautical_core.scheduler_service").SchedulerService
        cursor_module = importlib.import_module("nautical_core.scheduler_cursor")
    except (ImportError, AttributeError):
        return None
    return service, cursor_module.OccurrenceCursor, cursor_module.OccurrenceRangeRequest


def daily_timed_progress(task: Mapping[str, Any]) -> DailyProgress | None:
    recurrence = str(task.get("anchor") or task.get("anchor_file") or "")
    if "@t=" not in recurrence.lower():
        return None
    due = parse_task_date(str(task.get("due") or ""))
    scheduler = _load_nautical_scheduler()
    if due is None or scheduler is None:
        return None
    service_class, cursor_class, request_class = scheduler
    try:
        service = service_class.from_task(task)
        timezone = service.session.evaluator.context.timezone or due.tzinfo
        local_due = due.astimezone(timezone)
        day_start = datetime.combine(local_due.date(), time.min, timezone)
        day_end = datetime.combine(local_due.date(), time.max, timezone)
        request = request_class(
            cursor_class(day_start, inclusive=True, timezone=timezone),
            end_local=day_end,
            limit=256,
        )
        result = service.collect_request(request)
        if getattr(result, "failure", None) is not None:
            return None
        occurrences = [item.local_datetime for item in result.occurrences]
        return progress_from_occurrences(local_due, occurrences)
    except (AttributeError, LookupError, OSError, TypeError, ValueError):
        return None


def export_task(task_bin: str, uuid: str, timeout: float = 30) -> Mapping[str, Any] | None:
    try:
        result = subprocess.run(
            [task_bin, "rc.hooks:off", "rc.verbose:nothing", "rc.json.array:on", uuid, "export"],
            capture_output=True,
            text=True,
            check=False,
            timeout=timeout,
        )
        payload = json.loads(result.stdout or "[]") if result.returncode == 0 else []
    except (json.JSONDecodeError, OSError, subprocess.TimeoutExpired):
        return None
    return next((item for item in payload if isinstance(item, dict) and item.get("uuid") == uuid), None)


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        return 2
    task = export_task(
        argv[1], argv[2], float(os.environ.get("TW_COMMAND_TIMEOUT_SECONDS", "30"))
    )
    progress = daily_timed_progress(task or {})
    if progress is not None and progress.total > 1:
        print(f"{progress.position}|{progress.total}|{progress.remaining}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
