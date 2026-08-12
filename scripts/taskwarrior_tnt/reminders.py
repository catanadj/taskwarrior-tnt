"""Shared conversion of typed tasks into displayable reminders."""

from __future__ import annotations

from datetime import datetime

from taskwarrior_tnt.formatting import format_delta
from taskwarrior_tnt.models import Reminder, TaskRecord
from taskwarrior_tnt.policy import reminder_bucket, select_priority


def build_reminders(
    tasks: list[TaskRecord],
    now: datetime,
    past_hours: float,
    future_hours: float,
    max_tasks: int,
    snoozed: set[str] | None = None,
    always_show_active: bool = False,
) -> list[Reminder]:
    snoozed = snoozed or set()
    reminders: list[Reminder] = []
    for task in tasks:
        if task.uuid in snoozed:
            continue
        bucket = (
            "window"
            if always_show_active and task.started
            else reminder_bucket(task.due, now, past_hours, future_hours)
        )
        if bucket is None:
            continue
        action = "stop" if task.started else "start"
        button = "Stop" if task.started else "Start"
        if task.duration:
            start_time = task.due - task.duration
            time_text = f"{start_time:%H:%M} - {task.due:%H:%M}"
        else:
            start_time = task.due
            time_text = f"Due {task.due:%H:%M}"
        if task.started:
            status = "ACTIVE"
        elif bucket == "overdue":
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
        details = [status, delta]
        if task.project:
            details.append(task.project)
        if task.tags:
            details.append("+" + " +".join(task.tags[:3]))
        reminders.append(
            Reminder(
                bucket=bucket,
                uuid=task.uuid,
                title=f"{time_text} | {task.description or task.uuid[:8]}",
                content=" | ".join(details),
                action=action,
                button=button,
                due=task.due,
                urgency=task.urgency,
            )
        )
    return select_priority(
        reminders,
        max_tasks,
        due_key=lambda reminder: reminder.due,
        urgency_key=lambda reminder: reminder.urgency,
        bucket_key=lambda reminder: reminder.bucket,
        active_key=lambda reminder: reminder.action == "stop",
    )
