"""Legacy aggregate reminder output used by the original Tasker profile."""

from __future__ import annotations

import os
import sys
from datetime import datetime, timedelta

from taskwarrior_tnt.formatting import clean_text, format_delta
from taskwarrior_tnt.taskwarrior import export_pending, normalize_tasks


def render(past_hours: float, future_hours: float, max_tasks: int) -> list[str]:
    now_value = os.environ.get("TW_TEST_NOW")
    now = datetime.fromisoformat(now_value) if now_value else datetime.now().astimezone()
    if now.tzinfo is None:
        now = now.astimezone()
    start = now - timedelta(hours=past_hours)
    end = now + timedelta(hours=future_hours)
    tasks = normalize_tasks(export_pending(os.environ.get("TASK_BIN", "task"), now, future_hours))
    matches = []
    for task in tasks:
        if task.due is None:
            continue
        if not start <= task.due <= end:
            continue
        uuid = task.uuid[:8]
        if task.duration:
            start_time = task.due - task.duration
            prefix = f"{start_time:%H:%M}-{task.due:%H:%M}"
        else:
            start_time = task.due
            prefix = f"{task.due:%H:%M}"
        if task.due < start:
            status = "OVERDUE"
        elif now < start_time:
            status = "SOON"
        elif now <= task.due:
            status = "NOW"
        else:
            status = "DUE"
        if now < start_time:
            delta = f"starts in {format_delta(start_time - now)}"
        elif now > task.due:
            delta = f"due {format_delta(now - task.due)} ago"
        else:
            delta = f"due in {format_delta(task.due - now)}"
        detail = f"{status} | {task.description} - {delta}"
        if task.project:
            detail += f" ({task.project})"
        if task.tags:
            detail += " +" + "+".join(task.tags[:3])
        if uuid:
            detail += f" [{uuid}]"
        matches.append((task.due, -task.urgency, f"{prefix} {detail}"))
    matches.sort(key=lambda item: (item[0], item[1]))
    count = len(matches)
    output = [f"TW_COUNT={count}", f"TW_WINDOW={start:%H:%M}-{end:%H:%M}"]
    if not matches:
        return output + ["TW_TITLE=Taskwarrior", "TW_BODY=No due tasks in the reminder window."]
    shown = matches[:max_tasks]
    body = [line for _, _, line in shown]
    hidden = count - len(shown)
    if hidden:
        body.append(f"...and {hidden} more")
    output.append(f"TW_TITLE={count} Taskwarrior task{'s' if count != 1 else ''} due nearby")
    output.extend(["TW_BODY_START", "\n".join(body), "TW_BODY_END"])
    return output


if __name__ == "__main__":
    try:
        values = [float(sys.argv[1]), float(sys.argv[2]), int(sys.argv[3])]
        print("\n".join(render(*values)))
    except (IndexError, ValueError) as exc:
        print(f"ERROR: {clean_text(str(exc)) or 'invalid window settings'}")
        raise SystemExit(2)
