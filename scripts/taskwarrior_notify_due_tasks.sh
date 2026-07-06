#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

# Posts one Android notification per pending Taskwarrior task due in a window.
# Each notification includes a Done button that completes the task.

CONFIG_FILE="${TW_CONFIG_FILE:-$HOME/.termux/tasker/taskwarrior_tasker.conf}"
COMMAND="${1:-}"
DOCTOR_MODE=0
if [[ "$COMMAND" == "--doctor" ]]; then
  DOCTOR_MODE=1
fi

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

for config_name in \
  TW_WINDOW_PAST_HOURS \
  TW_WINDOW_FUTURE_HOURS \
  TW_MAX_TASKS \
  TW_DRY_RUN \
  TW_REORDER_EACH_RUN \
  TW_QUIET_HOURS_ENABLED \
  TW_QUIET_HOURS_START \
  TW_QUIET_HOURS_END \
  TW_EXECUTION_NOTIFICATION_GROUP \
  TW_OVERDUE_NOTIFICATION_GROUP \
  TW_GROUP_SUMMARY_ENABLED \
  TW_EXECUTION_GROUP_SUMMARY_ID \
  TW_OVERDUE_GROUP_SUMMARY_ID \
  TW_EXECUTION_NOTIFICATION_ICON \
  TW_OVERDUE_NOTIFICATION_ICON \
  TW_STARTED_NOTIFICATION_ICON \
  TW_NOTIFICATION_PRIORITY \
  TW_STARTED_NOTIFICATION_PRIORITY \
  TASK_BIN \
  TW_COMPLETE_SCRIPT \
  TW_FORGET_SCRIPT \
  TW_SNOOZE_SCRIPT \
  TW_START_STOP_SCRIPT \
  TW_NOTIFY_SCRIPT \
  TW_START_STOP_ACTION_ENABLED \
  TW_JOT_TIMELOG_ENABLED \
  JOT_BIN \
  TW_STATE_DIR \
  TW_GUI_CACHE_FILE; do
  remember_override "$config_name"
done

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
fi

for config_name in \
  TW_WINDOW_PAST_HOURS \
  TW_WINDOW_FUTURE_HOURS \
  TW_MAX_TASKS \
  TW_DRY_RUN \
  TW_REORDER_EACH_RUN \
  TW_QUIET_HOURS_ENABLED \
  TW_QUIET_HOURS_START \
  TW_QUIET_HOURS_END \
  TW_EXECUTION_NOTIFICATION_GROUP \
  TW_OVERDUE_NOTIFICATION_GROUP \
  TW_GROUP_SUMMARY_ENABLED \
  TW_EXECUTION_GROUP_SUMMARY_ID \
  TW_OVERDUE_GROUP_SUMMARY_ID \
  TW_EXECUTION_NOTIFICATION_ICON \
  TW_OVERDUE_NOTIFICATION_ICON \
  TW_STARTED_NOTIFICATION_ICON \
  TW_NOTIFICATION_PRIORITY \
  TW_STARTED_NOTIFICATION_PRIORITY \
  TASK_BIN \
  TW_COMPLETE_SCRIPT \
  TW_FORGET_SCRIPT \
  TW_SNOOZE_SCRIPT \
  TW_START_STOP_SCRIPT \
  TW_NOTIFY_SCRIPT \
  TW_START_STOP_ACTION_ENABLED \
  TW_JOT_TIMELOG_ENABLED \
  JOT_BIN \
  TW_STATE_DIR \
  TW_GUI_CACHE_FILE; do
  restore_override "$config_name"
done

WINDOW_PAST_HOURS="${TW_WINDOW_PAST_HOURS:-2}"
WINDOW_FUTURE_HOURS="${TW_WINDOW_FUTURE_HOURS:-2}"
MAX_TASKS="${TW_MAX_TASKS:-12}"
DRY_RUN="${TW_DRY_RUN:-0}"
REORDER_EACH_RUN="${TW_REORDER_EACH_RUN:-0}"
QUIET_HOURS_ENABLED="${TW_QUIET_HOURS_ENABLED:-0}"
QUIET_HOURS_START="${TW_QUIET_HOURS_START:-22:00}"
QUIET_HOURS_END="${TW_QUIET_HOURS_END:-07:00}"
EXECUTION_NOTIFICATION_GROUP="${TW_EXECUTION_NOTIFICATION_GROUP:-${TW_NOTIFICATION_GROUP:-taskwarrior-window}}"
OVERDUE_NOTIFICATION_GROUP="${TW_OVERDUE_NOTIFICATION_GROUP:-taskwarrior-overdue}"
GROUP_SUMMARY_ENABLED="${TW_GROUP_SUMMARY_ENABLED:-0}"
EXECUTION_GROUP_SUMMARY_ID="${TW_EXECUTION_GROUP_SUMMARY_ID:-${TW_GROUP_SUMMARY_ID:-999000}}"
OVERDUE_GROUP_SUMMARY_ID="${TW_OVERDUE_GROUP_SUMMARY_ID:-999001}"
EXECUTION_NOTIFICATION_ICON="${TW_EXECUTION_NOTIFICATION_ICON:-event_note}"
OVERDUE_NOTIFICATION_ICON="${TW_OVERDUE_NOTIFICATION_ICON:-warning}"
STARTED_NOTIFICATION_ICON="${TW_STARTED_NOTIFICATION_ICON:-play_arrow}"
NOTIFICATION_PRIORITY="${TW_NOTIFICATION_PRIORITY:-high}"
STARTED_NOTIFICATION_PRIORITY="${TW_STARTED_NOTIFICATION_PRIORITY:-high}"
TASK_BIN="${TASK_BIN:-task}"
COMPLETE_SCRIPT="${TW_COMPLETE_SCRIPT:-$HOME/.termux/tasker/taskwarrior_complete_task.sh}"
FORGET_SCRIPT="${TW_FORGET_SCRIPT:-$HOME/.termux/tasker/taskwarrior_forget_notification.sh}"
SNOOZE_SCRIPT="${TW_SNOOZE_SCRIPT:-$HOME/.termux/tasker/taskwarrior_snooze_task.sh}"
START_STOP_SCRIPT="${TW_START_STOP_SCRIPT:-$HOME/.termux/tasker/taskwarrior_start_stop_task.sh}"
START_STOP_ACTION_ENABLED="${TW_START_STOP_ACTION_ENABLED:-1}"
JOT_TIMELOG_ENABLED="${TW_JOT_TIMELOG_ENABLED:-1}"
JOT_BIN="${JOT_BIN:-jot}"
STATE_DIR="${TW_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/taskwarrior-tasker-notification}"
STATE_FILE="$STATE_DIR/active-notifications"
SNOOZE_FILE="$STATE_DIR/snoozed-tasks"
GUI_CACHE_FILE="${TW_GUI_CACHE_FILE:-$STATE_DIR/gui-cache.json}"
PROMOTE_UUID="${TW_PROMOTE_UUID:-}"
export TASK_BIN

if ! command -v "$TASK_BIN" >/dev/null 2>&1; then
  if [[ "$DOCTOR_MODE" == "1" ]]; then
    :
  else
    echo "ERROR: task command not found. Install Taskwarrior in Termux first."
    exit 2
  fi
fi

if ! command -v python3 >/dev/null 2>&1; then
  if [[ "$DOCTOR_MODE" == "1" ]]; then
    :
  else
    echo "ERROR: python3 command not found. Install Python in Termux first."
    exit 2
  fi
fi

if [[ "$DRY_RUN" != "1" ]] && ! command -v termux-notification >/dev/null 2>&1; then
  if [[ "$DOCTOR_MODE" == "1" ]]; then
    :
  else
    echo "ERROR: termux-notification not found. Install Termux:API and run: pkg install termux-api"
    exit 2
  fi
fi

if [[ "$DRY_RUN" != "1" && ! -x "$COMPLETE_SCRIPT" ]]; then
  if [[ "$DOCTOR_MODE" == "1" ]]; then
    :
  else
    echo "ERROR: complete action script is not executable: $COMPLETE_SCRIPT"
    exit 2
  fi
fi

if [[ "$DRY_RUN" != "1" && ! -x "$FORGET_SCRIPT" ]]; then
  if [[ "$DOCTOR_MODE" == "1" ]]; then
    :
  else
    echo "ERROR: forget action script is not executable: $FORGET_SCRIPT"
    exit 2
  fi
fi

if [[ "$DRY_RUN" != "1" && ! -x "$SNOOZE_SCRIPT" ]]; then
  if [[ "$DOCTOR_MODE" == "1" ]]; then
    :
  else
    echo "ERROR: snooze action script is not executable: $SNOOZE_SCRIPT"
    exit 2
  fi
fi

if [[ "$DRY_RUN" != "1" && "$START_STOP_ACTION_ENABLED" == "1" && ! -x "$START_STOP_SCRIPT" ]]; then
  if [[ "$DOCTOR_MODE" == "1" ]]; then
    :
  else
    echo "ERROR: Taskwarrior start/stop script is not executable: $START_STOP_SCRIPT"
    exit 2
  fi
fi

if [[ "$COMMAND" == "--test-notification" ]]; then
  termux-notification \
    --id 999001 \
    --title "Taskwarrior notification test" \
    --content "If you can see this, Termux:API notifications are working." \
    --priority high
  echo "Posted test notification 999001."
  exit 0
fi

in_quiet_hours() {
  python3 - "$QUIET_HOURS_ENABLED" "$QUIET_HOURS_START" "$QUIET_HOURS_END" <<'PY'
import re
import sys
from datetime import datetime

enabled, start_value, end_value = sys.argv[1:4]
if enabled != "1":
    raise SystemExit(1)

pattern = re.compile(r"^([01]\d|2[0-3]):([0-5]\d)$")
start_match = pattern.match(start_value)
end_match = pattern.match(end_value)
if not start_match or not end_match:
    print(f"ERROR: invalid quiet hours: {start_value}-{end_value}", file=sys.stderr)
    raise SystemExit(2)

start_minutes = int(start_match.group(1)) * 60 + int(start_match.group(2))
end_minutes = int(end_match.group(1)) * 60 + int(end_match.group(2))
now = datetime.now().astimezone()
now_minutes = now.hour * 60 + now.minute

if start_minutes == end_minutes:
    raise SystemExit(0)
if start_minutes < end_minutes:
    raise SystemExit(0 if start_minutes <= now_minutes < end_minutes else 1)
raise SystemExit(0 if now_minutes >= start_minutes or now_minutes < end_minutes else 1)
PY
}

doctor_check_command() {
  local command_name="$1"
  if command -v "$command_name" >/dev/null 2>&1; then
    echo "OK: $command_name found ($(command -v "$command_name"))"
  else
    echo "WARN: $command_name not found"
  fi
}

doctor_check_executable() {
  local label="$1"
  local path="$2"
  if [[ -x "$path" ]]; then
    echo "OK: $label executable: $path"
  elif [[ -e "$path" ]]; then
    echo "WARN: $label exists but is not executable: $path"
  else
    echo "WARN: $label missing: $path"
  fi
}

run_doctor() {
  echo "Taskwarrior Tasker doctor"
  echo
  echo "Config:"
  if [[ -f "$CONFIG_FILE" ]]; then
    echo "OK: config found: $CONFIG_FILE"
  else
    echo "WARN: config not found: $CONFIG_FILE"
  fi
  echo "Window: past=${WINDOW_PAST_HOURS}h future=${WINDOW_FUTURE_HOURS}h max=${MAX_TASKS}"
  echo "Quiet hours: enabled=$QUIET_HOURS_ENABLED start=$QUIET_HOURS_START end=$QUIET_HOURS_END"
  echo "Reorder each run: $REORDER_EACH_RUN"
  echo "Groups: window=$EXECUTION_NOTIFICATION_GROUP overdue=$OVERDUE_NOTIFICATION_GROUP summaries=$GROUP_SUMMARY_ENABLED"
  echo "Icons: window=$EXECUTION_NOTIFICATION_ICON overdue=$OVERDUE_NOTIFICATION_ICON started=$STARTED_NOTIFICATION_ICON"
  echo "Priority: default=$NOTIFICATION_PRIORITY started=$STARTED_NOTIFICATION_PRIORITY"
  echo "State dir: $STATE_DIR"
  echo

  echo "Commands:"
  doctor_check_command "$TASK_BIN"
  doctor_check_command python3
  doctor_check_command termux-notification
  doctor_check_command termux-notification-remove
  doctor_check_command termux-toast
  if [[ "$JOT_TIMELOG_ENABLED" == "1" ]]; then
    doctor_check_command "$JOT_BIN"
  fi
  echo

  echo "Action scripts:"
  doctor_check_executable "complete action" "$COMPLETE_SCRIPT"
  doctor_check_executable "forget action" "$FORGET_SCRIPT"
  doctor_check_executable "snooze action" "$SNOOZE_SCRIPT"
  doctor_check_executable "Taskwarrior start/stop action" "$START_STOP_SCRIPT"
  echo

  echo "State:"
  if [[ -d "$STATE_DIR" ]]; then
    echo "OK: state dir exists"
  else
    echo "WARN: state dir does not exist yet"
  fi
  if [[ -f "$STATE_FILE" ]]; then
    echo "Active notifications: $(grep -cve '^$' "$STATE_FILE" || true)"
  else
    echo "Active notifications: 0"
  fi
  if [[ -f "$SNOOZE_FILE" ]]; then
    echo "Snoozed tasks: $(grep -cve '^$' "$SNOOZE_FILE" || true)"
  else
    echo "Snoozed tasks: 0"
  fi
  echo

  echo "Quiet-hours state:"
  if in_quiet_hours; then
    echo "Quiet hours are active now."
  else
    echo "Quiet hours are not active now."
  fi
  echo

  echo "Taskwarrior export:"
  if command -v "$TASK_BIN" >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    if export_count="$("$TASK_BIN" rc.hooks:off rc.verbose:nothing rc.json.array:on status:pending export 2>/tmp/taskwarrior-tasker-doctor.err | python3 -c 'import json,sys; data=sys.stdin.read(); print(len(json.loads(data or "[]")))' 2>>/tmp/taskwarrior-tasker-doctor.err)"; then
      echo "OK: pending export returned $export_count task(s)"
    else
      echo "WARN: task export failed"
      if [[ -s /tmp/taskwarrior-tasker-doctor.err ]]; then
        sed -n '1,3p' /tmp/taskwarrior-tasker-doctor.err
      fi
    fi
    rm -f /tmp/taskwarrior-tasker-doctor.err
  else
    echo "SKIP: task export check needs task and python3"
  fi
  echo

  echo "Notification preview:"
  if [[ ! -d "$STATE_DIR" ]] && ! mkdir -p "$STATE_DIR" 2>/dev/null; then
    echo "SKIP: cannot create state dir: $STATE_DIR"
  elif command -v python3 >/dev/null 2>&1 && command -v "$TASK_BIN" >/dev/null 2>&1; then
    TW_DRY_RUN=1 TW_QUIET_HOURS_ENABLED=0 bash "$0" || true
  else
    echo "SKIP: preview needs task and python3"
  fi
}

if [[ "$DOCTOR_MODE" == "1" ]]; then
  run_doctor
  exit 0
fi

mkdir -p "$STATE_DIR"
touch "$SNOOZE_FILE"

declare -A stale_notifications=()
if [[ -f "$STATE_FILE" ]]; then
  while IFS= read -r previous_id; do
    if [[ -n "$previous_id" ]]; then
      stale_notifications["$previous_id"]=1
    fi
  done < "$STATE_FILE"
fi

records_file="$(mktemp)"
current_file="$(mktemp)"
trap 'rm -f "$records_file" "$current_file"' EXIT

if ! python3 - "$WINDOW_PAST_HOURS" "$WINDOW_FUTURE_HOURS" "$MAX_TASKS" "$SNOOZE_FILE" "$GUI_CACHE_FILE" > "$records_file" <<'PY'
import hashlib
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


def notification_id(uuid, bucket):
    digest = hashlib.sha1(uuid.encode("utf-8")).hexdigest()
    offset = 100000 if bucket == "window" else 1000000
    return offset + (int(digest[:8], 16) % 800000)


try:
    past_hours = float(sys.argv[1])
    future_hours = float(sys.argv[2])
    max_tasks = int(sys.argv[3])
    snooze_file = sys.argv[4]
    gui_cache_file = sys.argv[5]
except (IndexError, ValueError):
    print("ERROR\tinvalid window settings")
    sys.exit(2)

now = datetime.now().astimezone()
now_epoch = int(now.timestamp())
snoozed_until_by_uuid = {}
try:
    with open(snooze_file, "r", encoding="utf-8") as handle:
        for line in handle:
            uuid, _, until_epoch = line.strip().partition("\t")
            if not uuid or not until_epoch:
                continue
            try:
                until_epoch_int = int(until_epoch)
            except ValueError:
                continue
            if until_epoch_int > now_epoch:
                snoozed_until_by_uuid[uuid] = until_epoch_int
except FileNotFoundError:
    pass

task_bin = os.environ.get("TASK_BIN", "task")
end_for_filter = now + timedelta(hours=future_hours)
try:
    result = subprocess.run(
        [
            task_bin,
            "rc.hooks:off",
            "rc.verbose:nothing",
            "rc.json.array:on",
            "status:pending",
            f"due.before:{end_for_filter.strftime('%Y%m%dT%H%M%S')}",
            "export",
        ],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        result = subprocess.run(
            [
                task_bin,
                "rc.hooks:off",
                "rc.verbose:nothing",
                "rc.json.array:on",
                "status:pending",
                "export",
            ],
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
except OSError as exc:
    print(f"ERROR\ttask export failed: {exc}")
    sys.exit(2)

if result.returncode != 0:
    message = clean_text(result.stderr) or clean_text(result.stdout) or "task export failed"
    print(f"ERROR\t{message}")
    sys.exit(2)

try:
    tasks = json.loads(result.stdout or "[]")
except json.JSONDecodeError as exc:
    print(f"ERROR\ttask export did not return valid JSON: {exc}")
    sys.exit(2)

start = now - timedelta(hours=past_hours)
end = now + timedelta(hours=future_hours)
today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)

matches = []
for task in tasks:
    uuid = clean_text(task.get("uuid"))
    due = parse_task_date(task.get("due"))
    if not uuid or due is None or due < today_start or due > end:
        continue
    if uuid in snoozed_until_by_uuid:
        continue
    bucket = "overdue" if due < start else "window"

    urgency = float(task.get("urgency") or 0)
    description = clean_text(task.get("description"))
    project = clean_text(task.get("project"))
    tags = task.get("tags") or []
    duration = parse_iso_duration(task.get("duration"))
    is_started = bool(task.get("start"))
    task_action = "stop" if is_started else "start"
    task_button = "Stop" if task_action == "stop" else "Start"

    if duration:
        start_time = due - duration
        time_text = f"{start_time.strftime('%H:%M')} - {due.strftime('%H:%M')}"
    else:
        start_time = due
        time_text = f"Due {due.strftime('%H:%M')}"

    if bucket == "overdue":
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

    if is_started:
        status_text = f"ACTIVE {status_text}"

    content_parts = [status_text, delta_text]
    if project:
        content_parts.append(project)
    if tags:
        content_parts.append("+" + " +".join(tags[:3]))

    title = f"{time_text} | {description or uuid[:8]}"
    content = " | ".join(content_parts)
    started_value = "1" if is_started else "0"
    matches.append((bucket, due, -urgency, notification_id(uuid, bucket), uuid, title, content, task_action, task_button, started_value))

matches.sort(key=lambda item: (item[1], item[2]))
cache_rows = []
for bucket, due, urgency_sort, notif_id, uuid, title, content, task_action, task_button, started_value in matches[:max_tasks]:
    cache_rows.append(
        {
            "bucket": bucket,
            "uuid": uuid,
            "title": title,
            "content": content,
            "action": task_action,
            "button": task_button,
            "due": due.strftime("%Y%m%dT%H%M%S"),
            "urgency": -urgency_sort,
        }
    )

try:
    os.makedirs(os.path.dirname(gui_cache_file), exist_ok=True)
    with open(gui_cache_file, "w", encoding="utf-8") as handle:
        json.dump(
            {"generated_epoch": now_epoch, "tasks": cache_rows},
            handle,
            separators=(",", ":"),
        )
except OSError:
    pass

# Android tends to display the most recently posted notification at the top.
# Emit later tasks first so the closest due task is posted last and appears first.
for bucket, _, _, notif_id, uuid, title, content, task_action, task_button, started_value in reversed(matches[:max_tasks]):
    fields = [bucket, str(notif_id), uuid, title, content, task_action, task_button, started_value]
    print("\t".join(field.replace("\t", " ") for field in fields))
PY
then
  if [[ -s "$records_file" ]]; then
    while IFS=$'\t' read -r kind message; do
      if [[ "$kind" == "ERROR" ]]; then
        echo "ERROR: $message"
      else
        echo "$kind $message"
      fi
    done < "$records_file"
  else
    echo "ERROR: task export failed"
  fi
  exit 2
fi

if in_quiet_hours; then
  skipped_count="$(wc -l < "$records_file")"
  rm -f "$records_file" "$current_file"
  trap - EXIT
  echo "Quiet hours active; skipped $skipped_count Taskwarrior notification(s)."
  exit 0
fi

while IFS=$'\t' read -r bucket notification_id uuid title content task_action task_button started_value; do
  [[ -z "$notification_id" ]] && continue

  if [[ "$notification_id" == "ERROR" ]]; then
    echo "ERROR: $uuid"
    exit 2
  fi

  if [[ "$DRY_RUN" != "1" && ( "$REORDER_EACH_RUN" == "1" || "$uuid" == "$PROMOTE_UUID" ) ]]; then
    if command -v termux-notification-remove >/dev/null 2>&1; then
      termux-notification-remove "$notification_id" >/dev/null 2>&1 || true
    fi
  fi
done < "$records_file"

window_count=0
overdue_count=0
promoted_record=""

post_notification_record() {
  local bucket="$1"
  local notification_id="$2"
  local uuid="$3"
  local title="$4"
  local content="$5"
  local task_action="$6"
  local task_button="$7"
  local started_value="$8"
  local notification_group notification_icon notification_priority
  local complete_action delete_action snooze_hour_action snooze_tomorrow_action
  local button1_text button1_action

  [[ -z "$notification_id" ]] && return 0

  if [[ "$notification_id" == "ERROR" ]]; then
    echo "ERROR: $uuid"
    exit 2
  fi

  stale_notifications["$notification_id"]=""
  printf '%s\n' "$notification_id" >> "$current_file"
  if [[ "$bucket" == "overdue" ]]; then
    overdue_count=$((overdue_count + 1))
    notification_group="$OVERDUE_NOTIFICATION_GROUP"
    notification_icon="$OVERDUE_NOTIFICATION_ICON"
    notification_priority="$NOTIFICATION_PRIORITY"
  else
    window_count=$((window_count + 1))
    notification_group="$EXECUTION_NOTIFICATION_GROUP"
    notification_icon="$EXECUTION_NOTIFICATION_ICON"
    notification_priority="$NOTIFICATION_PRIORITY"
  fi
  if [[ "$started_value" == "1" ]]; then
    notification_icon="$STARTED_NOTIFICATION_ICON"
    notification_priority="$STARTED_NOTIFICATION_PRIORITY"
  fi

  complete_action="$COMPLETE_SCRIPT $uuid $notification_id"
  delete_action="$FORGET_SCRIPT $notification_id"
  snooze_hour_action="$SNOOZE_SCRIPT $uuid $notification_id 1h"
  snooze_tomorrow_action="$SNOOZE_SCRIPT $uuid $notification_id tomorrow"
  if [[ "$START_STOP_ACTION_ENABLED" == "1" ]]; then
    button1_text="$task_button"
    button1_action="$START_STOP_SCRIPT $task_action $uuid"
  else
    button1_text="Snooze 1h"
    button1_action="$snooze_hour_action"
  fi
  if [[ "$DRY_RUN" == "1" ]]; then
    printf 'DRY_RUN id=%s uuid=%s reorder=%s title=%s content=%s button1=%s button2=Done action=%s\n' "$notification_id" "$uuid" "$REORDER_EACH_RUN" "$title" "$content" "$button1_text" "$complete_action"
  else
    termux-notification \
      --id "$notification_id" \
      --title "$title" \
      --content "$content" \
      --icon "$notification_icon" \
      --button1 "$button1_text" \
      --button1-action "$button1_action" \
      --button2 "Done" \
      --button2-action "$complete_action" \
      --button3 "Tomorrow" \
      --button3-action "$snooze_tomorrow_action" \
      --on-delete "$delete_action" \
      --alert-once \
      --group "$notification_group" \
      --priority "$notification_priority"
    if [[ "$REORDER_EACH_RUN" == "1" ]]; then
      echo "Reposted: $notification_id $title"
    else
      echo "Posted or updated: $notification_id $title"
    fi
  fi
}

while IFS=$'\t' read -r bucket notification_id uuid title content task_action task_button started_value; do
  if [[ -n "$PROMOTE_UUID" && "$uuid" == "$PROMOTE_UUID" ]]; then
    promoted_record="$bucket"$'\t'"$notification_id"$'\t'"$uuid"$'\t'"$title"$'\t'"$content"$'\t'"$task_action"$'\t'"$task_button"$'\t'"$started_value"
    continue
  fi
  post_notification_record "$bucket" "$notification_id" "$uuid" "$title" "$content" "$task_action" "$task_button" "$started_value"
done < "$records_file"

if [[ -n "$promoted_record" ]]; then
  IFS=$'\t' read -r bucket notification_id uuid title content task_action task_button started_value <<< "$promoted_record"
  post_notification_record "$bucket" "$notification_id" "$uuid" "$title" "$content" "$task_action" "$task_button" "$started_value"
fi

if [[ "$DRY_RUN" != "1" && "$GROUP_SUMMARY_ENABLED" == "1" ]]; then
  if [[ "$window_count" -gt 0 ]]; then
    termux-notification \
      --id "$EXECUTION_GROUP_SUMMARY_ID" \
      --title "Taskwarrior window" \
      --content "$window_count task notification(s)" \
      --group "$EXECUTION_NOTIFICATION_GROUP" \
      --alert-once \
      --priority low
  elif command -v termux-notification-remove >/dev/null 2>&1; then
    termux-notification-remove "$EXECUTION_GROUP_SUMMARY_ID" >/dev/null 2>&1 || true
  fi

  if [[ "$overdue_count" -gt 0 ]]; then
    termux-notification \
      --id "$OVERDUE_GROUP_SUMMARY_ID" \
      --title "Taskwarrior overdue" \
      --content "$overdue_count overdue task notification(s)" \
      --group "$OVERDUE_NOTIFICATION_GROUP" \
      --alert-once \
      --priority low
  elif command -v termux-notification-remove >/dev/null 2>&1; then
    termux-notification-remove "$OVERDUE_GROUP_SUMMARY_ID" >/dev/null 2>&1 || true
  fi
fi

for notification_id in "${!stale_notifications[@]}"; do
  if [[ -n "${stale_notifications[$notification_id]}" ]] && command -v termux-notification-remove >/dev/null 2>&1; then
    termux-notification-remove "$notification_id" >/dev/null 2>&1 || true
  fi
done

mv "$current_file" "$STATE_FILE"
rm -f "$records_file" "$current_file"
trap - EXIT

echo "Posted $(wc -l < "$STATE_FILE") Taskwarrior notification(s)."
