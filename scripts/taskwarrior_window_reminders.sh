#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

# Prints pending Taskwarrior tasks whose due date is inside a time window.
# Intended for Termux:Tasker. Tasker can use stdout as notification text.

CONFIG_FILE="${TW_CONFIG_FILE:-$HOME/.termux/tasker/taskwarrior_tasker.conf}"

remember_override() {
  local name="$1"
  local set_var="__${name}_was_set"
  local value_var="__${name}_value"

  if [[ ${!name+x} ]]; then
    printf -v "$set_var" '%s' 1
    printf -v "$value_var" '%s' "${!name}"
  else
    printf -v "$set_var" '%s' 0
    printf -v "$value_var" '%s' ''
  fi
}

restore_override() {
  local name="$1"
  local set_var="__${name}_was_set"
  local value_var="__${name}_value"

  if [[ "${!set_var}" == "1" ]]; then
    printf -v "$name" '%s' "${!value_var}"
  fi
}

for config_name in TW_WINDOW_PAST_HOURS TW_WINDOW_FUTURE_HOURS TW_MAX_TASKS TASK_BIN; do
  remember_override "$config_name"
done

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
fi

for config_name in TW_WINDOW_PAST_HOURS TW_WINDOW_FUTURE_HOURS TW_MAX_TASKS TASK_BIN; do
  restore_override "$config_name"
done

WINDOW_PAST_HOURS="${TW_WINDOW_PAST_HOURS:-2}"
WINDOW_FUTURE_HOURS="${TW_WINDOW_FUTURE_HOURS:-2}"
MAX_TASKS="${TW_MAX_TASKS:-12}"
TASK_BIN="${TASK_BIN:-task}"
export TASK_BIN

if ! command -v "$TASK_BIN" >/dev/null 2>&1; then
  echo "ERROR: task command not found. Install Taskwarrior in Termux first."
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 command not found. Install Python in Termux first."
  exit 2
fi

python3 - "$WINDOW_PAST_HOURS" "$WINDOW_FUTURE_HOURS" "$MAX_TASKS" <<'PY'
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone


def parse_task_date(value):
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


def clean_text(value):
    return " ".join(str(value or "").split())


def parse_iso_duration(value):
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

    values = {key: float(value or 0) for key, value in match.groupdict().items()}
    duration = timedelta(
        days=values["days"],
        hours=values["hours"],
        minutes=values["minutes"],
        seconds=values["seconds"],
    )
    return duration if duration.total_seconds() > 0 else None


def format_delta(delta):
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


try:
    past_hours = float(sys.argv[1])
    future_hours = float(sys.argv[2])
    max_tasks = int(sys.argv[3])
except (IndexError, ValueError):
    print("ERROR: invalid window settings")
    sys.exit(2)

task_bin = os.environ.get("TASK_BIN", "task")
try:
    result = subprocess.run(
        [
            task_bin,
            "rc.hooks:off",
            "rc.verbose:nothing",
            "rc.json.array:on",
            "status:pending",
            "export",
        ],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
except subprocess.CalledProcessError as exc:
    message = clean_text(exc.stderr) or clean_text(exc.stdout) or str(exc)
    print(f"ERROR: task export failed: {message}")
    sys.exit(2)

try:
    tasks = json.loads(result.stdout or "[]")
except json.JSONDecodeError as exc:
    print(f"ERROR: task export did not return valid JSON: {exc}")
    sys.exit(2)

now = datetime.now().astimezone()
start = now - timedelta(hours=past_hours)
end = now + timedelta(hours=future_hours)

matches = []
for task in tasks:
    due = parse_task_date(task.get("due"))
    if due is None or not (start <= due <= end):
        continue

    urgency = float(task.get("urgency") or 0)
    description = clean_text(task.get("description"))
    project = clean_text(task.get("project"))
    tags = task.get("tags") or []
    uuid = clean_text(task.get("uuid"))[:8]
    duration = parse_iso_duration(task.get("duration"))

    if duration:
        start_time = due - duration
        prefix = f"{start_time.strftime('%H:%M')}-{due.strftime('%H:%M')}"
    else:
        start_time = due
        prefix = due.strftime("%H:%M")

    if due < start:
        status_text = "OVERDUE"
    elif now < start_time:
        status_text = "SOON"
    elif now <= due:
        status_text = "NOW"
    else:
        status_text = "DUE"

    if now < start_time:
        delta_text = f"starts in {format_delta(start_time - now)}"
    elif now > due:
        delta_text = f"due {format_delta(now - due)} ago"
    else:
        delta_text = f"due in {format_delta(due - now)}"

    detail = f"{status_text} | {description} - {delta_text}"
    if project:
        detail = f"{detail} ({project})"
    if tags:
        detail = f"{detail} +{'+'.join(tags[:3])}"
    if uuid:
        detail = f"{detail} [{uuid}]"

    matches.append((due, -urgency, f"{prefix} {detail}"))

matches.sort(key=lambda item: (item[0], item[1]))

count = len(matches)
print(f"TW_COUNT={count}")
print(f"TW_WINDOW={start.strftime('%H:%M')}-{end.strftime('%H:%M')}")

if not matches:
    print("TW_TITLE=Taskwarrior")
    print("TW_BODY=No due tasks in the reminder window.")
    sys.exit(0)

shown = matches[:max_tasks]
hidden_count = count - len(shown)
title = f"{count} Taskwarrior task{'s' if count != 1 else ''} due nearby"
body_lines = [line for _, _, line in shown]
if hidden_count > 0:
    body_lines.append(f"...and {hidden_count} more")

print(f"TW_TITLE={title}")
print("TW_BODY_START")
print("\n".join(body_lines))
print("TW_BODY_END")
PY
