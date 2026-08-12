"""Generate notification records for the shell notification orchestrator."""

from __future__ import annotations

import hashlib
import json
import os
import sys
from datetime import datetime

from taskwarrior_tnt.formatting import clean_text
from taskwarrior_tnt.policy import filter_tasks
from taskwarrior_tnt.reminders import build_reminders
from taskwarrior_tnt.state import read_snoozes
from taskwarrior_tnt.taskwarrior import export_pending, normalize_tasks


def notification_id(uuid: str, bucket: str) -> int:
    digest = hashlib.sha1(uuid.encode("utf-8")).hexdigest()
    offset = 100000 if bucket == "window" else 1000000
    return offset + (int(digest[:8], 16) % 800000)


def generate_records(
    past_hours: float,
    future_hours: float,
    max_tasks: int,
    snooze_file: str,
    gui_cache_file: str,
    notification_config_signature: str,
) -> list[str]:
    if past_hours < 0 or future_hours < 0 or max_tasks < 1:
        raise ValueError("window hours must be non-negative and max tasks must be at least 1")
    now_value = os.environ.get("TW_TEST_NOW")
    now = datetime.fromisoformat(now_value) if now_value else datetime.now().astimezone()
    if now.tzinfo is None:
        now = now.astimezone()
    now_epoch = int(now.timestamp())
    snoozed = read_snoozes(snooze_file, now_epoch)
    task_bin = os.environ.get("TASK_BIN", "task")
    tasks = filter_tasks(
        normalize_tasks(
            export_pending(
            task_bin,
            now,
            future_hours,
            task_filter=os.environ.get("TW_TASK_FILTER", ""),
            timeout_seconds=float(os.environ.get("TW_COMMAND_TIMEOUT_SECONDS", "30")),
        )
        ),
        include_projects=os.environ.get("TW_INCLUDE_PROJECTS", ""),
        exclude_projects=os.environ.get("TW_EXCLUDE_PROJECTS", ""),
        include_tags=os.environ.get("TW_INCLUDE_TAGS", ""),
        exclude_tags=os.environ.get("TW_EXCLUDE_TAGS", ""),
        opt_out_tag=os.environ.get("TW_OPTOUT_TAG", ""),
    )
    reminders = build_reminders(
        tasks,
        now,
        past_hours,
        future_hours,
        max_tasks,
        set(snoozed),
        os.environ.get("TW_ALWAYS_SHOW_ACTIVE", "0") == "1",
    )
    cache_rows = [
        {
            "bucket": reminder.bucket,
            "uuid": reminder.uuid,
            "title": reminder.title,
            "content": reminder.content,
            "action": reminder.action,
            "button": reminder.button,
            "due": reminder.due.strftime("%Y%m%dT%H%M%S"),
            "urgency": reminder.urgency,
        }
        for reminder in reminders
    ]
    try:
        os.makedirs(os.path.dirname(gui_cache_file), exist_ok=True)
        with open(gui_cache_file, "w", encoding="utf-8") as handle:
            json.dump({"generated_epoch": now_epoch, "tasks": cache_rows}, handle, separators=(",", ":"))
    except OSError:
        pass

    records: list[str] = []
    for reminder in reversed(reminders):
        started = "1" if reminder.action == "stop" else "0"
        fingerprint = hashlib.sha256(
            json.dumps(
                [
                    reminder.bucket,
                    reminder.title,
                    reminder.content,
                    reminder.action,
                    reminder.button,
                    started,
                    notification_config_signature,
                ],
                ensure_ascii=False,
                separators=(",", ":"),
            ).encode("utf-8")
        ).hexdigest()[:20]
        fields = [
            reminder.bucket,
            str(notification_id(reminder.uuid, reminder.bucket)),
            reminder.uuid,
            reminder.title,
            reminder.content,
            reminder.action,
            reminder.button,
            started,
            fingerprint,
        ]
        records.append("\t".join(field.replace("\t", " ") for field in fields))
    return records


def main() -> int:
    try:
        args = sys.argv[1:]
        records = generate_records(float(args[0]), float(args[1]), int(args[2]), *args[3:6])
    except (IndexError, ValueError) as exc:
        print(f"ERROR\t{clean_text(str(exc)) or 'invalid window settings'}")
        return 2
    except Exception as exc:
        print(f"ERROR\t{clean_text(str(exc)) or 'task export failed'}")
        return 2
    print("\n".join(records))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
