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
  TW_NOTIFICATION_CHANNELS_ENABLED \
  TW_EXECUTION_NOTIFICATION_CHANNEL \
  TW_EXECUTION_NOTIFICATION_CHANNEL_NAME \
  TW_OVERDUE_NOTIFICATION_CHANNEL \
  TW_OVERDUE_NOTIFICATION_CHANNEL_NAME \
  TW_STARTED_NOTIFICATION_CHANNEL \
  TW_STARTED_NOTIFICATION_CHANNEL_NAME \
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
  TW_COMMON_SCRIPT \
  TW_STATE_DIR \
  TW_GUI_CACHE_FILE \
  TW_TEST_NOW; do
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
  TW_NOTIFICATION_CHANNELS_ENABLED \
  TW_EXECUTION_NOTIFICATION_CHANNEL \
  TW_EXECUTION_NOTIFICATION_CHANNEL_NAME \
  TW_OVERDUE_NOTIFICATION_CHANNEL \
  TW_OVERDUE_NOTIFICATION_CHANNEL_NAME \
  TW_STARTED_NOTIFICATION_CHANNEL \
  TW_STARTED_NOTIFICATION_CHANNEL_NAME \
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
  TW_COMMON_SCRIPT \
  TW_STATE_DIR \
  TW_GUI_CACHE_FILE \
  TW_TEST_NOW; do
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
NOTIFICATION_CHANNELS_ENABLED="${TW_NOTIFICATION_CHANNELS_ENABLED:-1}"
EXECUTION_NOTIFICATION_CHANNEL="${TW_EXECUTION_NOTIFICATION_CHANNEL:-taskwarrior-tnt-window}"
EXECUTION_NOTIFICATION_CHANNEL_NAME="${TW_EXECUTION_NOTIFICATION_CHANNEL_NAME:-Taskwarrior TNT window}"
OVERDUE_NOTIFICATION_CHANNEL="${TW_OVERDUE_NOTIFICATION_CHANNEL:-taskwarrior-tnt-overdue}"
OVERDUE_NOTIFICATION_CHANNEL_NAME="${TW_OVERDUE_NOTIFICATION_CHANNEL_NAME:-Taskwarrior TNT overdue}"
STARTED_NOTIFICATION_CHANNEL="${TW_STARTED_NOTIFICATION_CHANNEL:-taskwarrior-tnt-active}"
STARTED_NOTIFICATION_CHANNEL_NAME="${TW_STARTED_NOTIFICATION_CHANNEL_NAME:-Taskwarrior TNT active}"
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
COMMON_SCRIPT="${TW_COMMON_SCRIPT:-$(dirname "$0")/taskwarrior_tnt_common.sh}"
STATE_DIR="${TW_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/taskwarrior-tnt}"
STATE_FILE="$STATE_DIR/active-notifications"
SNOOZE_FILE="$STATE_DIR/snoozed-tasks"
CHANNEL_STATE_FILE="$STATE_DIR/notification-channels"
GUI_CACHE_FILE="${TW_GUI_CACHE_FILE:-$STATE_DIR/gui-cache.json}"
PROMOTE_UUID="${TW_PROMOTE_UUID:-}"
CHANNELS_ACTIVE=0
CHANNEL_SIGNATURE="$EXECUTION_NOTIFICATION_CHANNEL|$EXECUTION_NOTIFICATION_CHANNEL_NAME|$OVERDUE_NOTIFICATION_CHANNEL|$OVERDUE_NOTIFICATION_CHANNEL_NAME|$STARTED_NOTIFICATION_CHANNEL|$STARTED_NOTIFICATION_CHANNEL_NAME"
NOTIFICATION_CONFIG_SIGNATURE="schema=2|$EXECUTION_NOTIFICATION_GROUP|$OVERDUE_NOTIFICATION_GROUP|$EXECUTION_NOTIFICATION_ICON|$OVERDUE_NOTIFICATION_ICON|$STARTED_NOTIFICATION_ICON|$NOTIFICATION_CHANNELS_ENABLED|$CHANNEL_SIGNATURE|$NOTIFICATION_PRIORITY|$STARTED_NOTIFICATION_PRIORITY|$COMPLETE_SCRIPT|$FORGET_SCRIPT|$SNOOZE_SCRIPT|$START_STOP_SCRIPT|$START_STOP_ACTION_ENABLED"
export TASK_BIN
SCRIPT_DIR="$(dirname "$0")"
export PYTHONPATH="$SCRIPT_DIR${PYTHONPATH:+:$PYTHONPATH}"

if [[ ! -r "$COMMON_SCRIPT" ]]; then
  echo "ERROR: shared helper is missing: $COMMON_SCRIPT"
  exit 2
fi
# shellcheck source=/dev/null
source "$COMMON_SCRIPT"

setup_notification_channels() {
  local force="${1:-0}"
  local current_signature=""
  local tmp_file output

  if [[ "$NOTIFICATION_CHANNELS_ENABLED" != "1" ]]; then
    return 0
  fi
  if ! command -v termux-notification-channel >/dev/null 2>&1; then
    echo "WARN: termux-notification-channel not found; using the default Android channel." >&2
    return 1
  fi
  if [[ -z "$EXECUTION_NOTIFICATION_CHANNEL" ||
        -z "$EXECUTION_NOTIFICATION_CHANNEL_NAME" ||
        -z "$OVERDUE_NOTIFICATION_CHANNEL" ||
        -z "$OVERDUE_NOTIFICATION_CHANNEL_NAME" ||
        -z "$STARTED_NOTIFICATION_CHANNEL" ||
        -z "$STARTED_NOTIFICATION_CHANNEL_NAME" ]]; then
    echo "WARN: notification channel ids and names must not be empty; using the default Android channel." >&2
    return 1
  fi

  mkdir -p "$STATE_DIR"
  if [[ -f "$CHANNEL_STATE_FILE" ]]; then
    IFS= read -r current_signature < "$CHANNEL_STATE_FILE" || true
  fi
  if [[ "$force" != "1" && "$current_signature" == "$CHANNEL_SIGNATURE" ]]; then
    CHANNELS_ACTIVE=1
    return 0
  fi

  if ! output="$(termux-notification-channel "$EXECUTION_NOTIFICATION_CHANNEL" "$EXECUTION_NOTIFICATION_CHANNEL_NAME" 2>&1)"; then
    echo "WARN: could not create execution notification channel: $output" >&2
    return 1
  fi
  if ! output="$(termux-notification-channel "$OVERDUE_NOTIFICATION_CHANNEL" "$OVERDUE_NOTIFICATION_CHANNEL_NAME" 2>&1)"; then
    echo "WARN: could not create overdue notification channel: $output" >&2
    return 1
  fi
  if ! output="$(termux-notification-channel "$STARTED_NOTIFICATION_CHANNEL" "$STARTED_NOTIFICATION_CHANNEL_NAME" 2>&1)"; then
    echo "WARN: could not create active notification channel: $output" >&2
    return 1
  fi

  tmp_file="$(mktemp)"
  printf '%s\n' "$CHANNEL_SIGNATURE" > "$tmp_file"
  mv "$tmp_file" "$CHANNEL_STATE_FILE"
  CHANNELS_ACTIVE=1
}

if [[ "$COMMAND" == "--setup-channels" ]]; then
  if [[ "$NOTIFICATION_CHANNELS_ENABLED" != "1" ]]; then
    echo "Notification channels are disabled in $CONFIG_FILE."
    exit 0
  fi
  if setup_notification_channels 1; then
    echo "Created or refreshed Taskwarrior TNT notification channels."
    exit 0
  fi
  exit 2
fi

if [[ "$DRY_RUN" != "1" && "$DOCTOR_MODE" != "1" ]]; then
  setup_notification_channels 0 || true
fi
NOTIFICATION_CONFIG_SIGNATURE="$NOTIFICATION_CONFIG_SIGNATURE|channels_active=$CHANNELS_ACTIVE"

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
  test_channel_args=()
  if [[ "$CHANNELS_ACTIVE" == "1" ]]; then
    test_channel_args=(--channel "$EXECUTION_NOTIFICATION_CHANNEL")
  fi
  termux-notification "${test_channel_args[@]}" \
    --id 998999 \
    --title "Taskwarrior TNT test" \
    --content "If you can see this, Termux:API notifications are working." \
    --priority high
  echo "Posted test notification 998999."
  exit 0
fi

in_quiet_hours() {
  python3 - "$QUIET_HOURS_ENABLED" "$QUIET_HOURS_START" "$QUIET_HOURS_END" <<'PY'
import os
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
now_value = os.environ.get("TW_TEST_NOW")
try:
    now = datetime.fromisoformat(now_value) if now_value else datetime.now().astimezone()
except ValueError:
    print(f"ERROR: invalid TW_TEST_NOW: {now_value}", file=sys.stderr)
    raise SystemExit(2)
if now.tzinfo is None:
    now = now.astimezone()
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
  echo "Taskwarrior TNT doctor"
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
  echo "Channels: enabled=$NOTIFICATION_CHANNELS_ENABLED window=$EXECUTION_NOTIFICATION_CHANNEL overdue=$OVERDUE_NOTIFICATION_CHANNEL active=$STARTED_NOTIFICATION_CHANNEL"
  echo "Icons: window=$EXECUTION_NOTIFICATION_ICON overdue=$OVERDUE_NOTIFICATION_ICON started=$STARTED_NOTIFICATION_ICON"
  echo "Priority: default=$NOTIFICATION_PRIORITY started=$STARTED_NOTIFICATION_PRIORITY"
  if [[ "$NOTIFICATION_CHANNELS_ENABLED" != "1" ]]; then
    echo "Channel setup: disabled"
  elif [[ -f "$CHANNEL_STATE_FILE" ]] && IFS= read -r doctor_channel_signature < "$CHANNEL_STATE_FILE" &&
       [[ "$doctor_channel_signature" == "$CHANNEL_SIGNATURE" ]]; then
    echo "Channel setup: initialized"
  else
    echo "Channel setup: pending (run $0 --setup-channels)"
  fi
  echo "State dir: $STATE_DIR"
  echo

  echo "Commands:"
  doctor_check_command "$TASK_BIN"
  doctor_check_command python3
  doctor_check_command termux-notification
  doctor_check_command termux-notification-channel
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
    if export_count="$("$TASK_BIN" rc.hooks:off rc.verbose:nothing rc.json.array:on status:pending export 2>/tmp/taskwarrior-tnt-doctor.err | python3 -c 'import json,sys; data=sys.stdin.read(); print(len(json.loads(data or "[]")))' 2>>/tmp/taskwarrior-tnt-doctor.err)"; then
      echo "OK: pending export returned $export_count task(s)"
    else
      echo "WARN: task export failed"
      if [[ -s /tmp/taskwarrior-tnt-doctor.err ]]; then
        sed -n '1,3p' /tmp/taskwarrior-tnt-doctor.err
      fi
    fi
    rm -f /tmp/taskwarrior-tnt-doctor.err
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
tnt_acquire_state_lock "$STATE_DIR"
touch "$SNOOZE_FILE"

declare -A stale_notifications=()
declare -A previous_fingerprints=()
if [[ -f "$STATE_FILE" ]]; then
  while IFS=$'\t' read -r previous_id _ previous_fingerprint _; do
    if [[ -n "$previous_id" ]]; then
      stale_notifications["$previous_id"]=1
      previous_fingerprints["$previous_id"]="$previous_fingerprint"
    fi
  done < "$STATE_FILE"
fi

records_file="$(mktemp)"
current_file="$(mktemp)"
cleanup() {
  rm -f "$records_file" "$current_file"
  tnt_release_state_lock
}
trap cleanup EXIT

if ! python3 - "$WINDOW_PAST_HOURS" "$WINDOW_FUTURE_HOURS" "$MAX_TASKS" "$SNOOZE_FILE" "$GUI_CACHE_FILE" "$NOTIFICATION_CONFIG_SIGNATURE" > "$records_file" <<'PY'
import hashlib
import json
import os
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from taskwarrior_tnt.formatting import clean_text
from taskwarrior_tnt.reminders import build_reminders
from taskwarrior_tnt.state import read_snoozes
from taskwarrior_tnt.taskwarrior import export_pending, normalize_tasks


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
    notification_config_signature = sys.argv[6]
except (IndexError, ValueError):
    print("ERROR\tinvalid window settings")
    sys.exit(2)
if past_hours < 0 or future_hours < 0 or max_tasks < 1:
    print("ERROR\twindow hours must be non-negative and max tasks must be at least 1")
    sys.exit(2)

now_value = os.environ.get("TW_TEST_NOW")
try:
    now = datetime.fromisoformat(now_value) if now_value else datetime.now().astimezone()
except ValueError:
    print(f"ERROR\tinvalid TW_TEST_NOW: {now_value}")
    sys.exit(2)
if now.tzinfo is None:
    now = now.astimezone()
now_epoch = int(now.timestamp())
snoozed_until_by_uuid = read_snoozes(snooze_file, now_epoch)

task_bin = os.environ.get("TASK_BIN", "task")
try:
    tasks = normalize_tasks(export_pending(task_bin, now, future_hours))
except Exception as exc:
    print(f"ERROR\t{clean_text(str(exc))}")
    sys.exit(2)

selected_reminders = build_reminders(
    tasks,
    now,
    past_hours,
    future_hours,
    max_tasks,
    set(snoozed_until_by_uuid),
)

selected_matches = []
for reminder in selected_reminders:
    started_value = "1" if reminder.action == "stop" else "0"
    selected_matches.append(
        (
            reminder.bucket,
            reminder.due,
            -reminder.urgency,
            notification_id(reminder.uuid, reminder.bucket),
            reminder.uuid,
            reminder.title,
            reminder.content,
            reminder.action,
            reminder.button,
            started_value,
        )
    )

cache_rows = []
for bucket, due, urgency_sort, notif_id, uuid, title, content, task_action, task_button, started_value in selected_matches:
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
for bucket, _, _, notif_id, uuid, title, content, task_action, task_button, started_value in reversed(selected_matches):
    fingerprint = hashlib.sha256(
        json.dumps(
            [
                bucket,
                title,
                content,
                task_action,
                task_button,
                started_value,
                notification_config_signature,
            ],
            ensure_ascii=False,
            separators=(",", ":"),
        ).encode("utf-8")
    ).hexdigest()[:20]
    fields = [bucket, str(notif_id), uuid, title, content, task_action, task_button, started_value, fingerprint]
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
  echo "Quiet hours active; skipped $skipped_count Taskwarrior notification(s)."
  exit 0
fi

while IFS=$'\t' read -r bucket notification_id uuid title content task_action task_button started_value fingerprint; do
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
  local fingerprint="$9"
  local notification_group notification_icon notification_priority notification_channel
  local complete_action delete_action snooze_hour_action snooze_tomorrow_action
  local button1_text button1_action
  local -a channel_args=()

  [[ -z "$notification_id" ]] && return 0

  if [[ "$notification_id" == "ERROR" ]]; then
    echo "ERROR: $uuid"
    exit 2
  fi

  stale_notifications["$notification_id"]=""
  printf '%s\t%s\t%s\n' "$notification_id" "$uuid" "$fingerprint" >> "$current_file"
  if [[ "$bucket" == "overdue" ]]; then
    overdue_count=$((overdue_count + 1))
    notification_group="$OVERDUE_NOTIFICATION_GROUP"
    notification_icon="$OVERDUE_NOTIFICATION_ICON"
    notification_priority="$NOTIFICATION_PRIORITY"
    notification_channel="$OVERDUE_NOTIFICATION_CHANNEL"
  else
    window_count=$((window_count + 1))
    notification_group="$EXECUTION_NOTIFICATION_GROUP"
    notification_icon="$EXECUTION_NOTIFICATION_ICON"
    notification_priority="$NOTIFICATION_PRIORITY"
    notification_channel="$EXECUTION_NOTIFICATION_CHANNEL"
  fi
  if [[ "$started_value" == "1" ]]; then
    notification_icon="$STARTED_NOTIFICATION_ICON"
    notification_priority="$STARTED_NOTIFICATION_PRIORITY"
    notification_channel="$STARTED_NOTIFICATION_CHANNEL"
  fi
  if [[ "$CHANNELS_ACTIVE" == "1" ]]; then
    channel_args=(--channel "$notification_channel")
  fi

  complete_action="$COMPLETE_SCRIPT $uuid $notification_id"
  delete_action="$FORGET_SCRIPT $notification_id"
  snooze_hour_action="$SNOOZE_SCRIPT $uuid $notification_id 1h"
  snooze_tomorrow_action="$SNOOZE_SCRIPT $uuid $notification_id tomorrow"
  if [[ "$START_STOP_ACTION_ENABLED" == "1" ]]; then
    button1_text="$task_button"
    button1_action="$START_STOP_SCRIPT $task_action $uuid $notification_id"
  else
    button1_text="Snooze 1h"
    button1_action="$snooze_hour_action"
  fi
  if [[ "$DRY_RUN" != "1" &&
        "$REORDER_EACH_RUN" != "1" &&
        "$uuid" != "$PROMOTE_UUID" &&
        "${previous_fingerprints[$notification_id]:-}" == "$fingerprint" ]]; then
    echo "Unchanged: $notification_id $title"
    return 0
  fi
  if [[ "$DRY_RUN" == "1" ]]; then
    printf 'DRY_RUN id=%s uuid=%s channel=%s reorder=%s title=%s content=%s button1=%s button2=Done action=%s\n' "$notification_id" "$uuid" "$notification_channel" "$REORDER_EACH_RUN" "$title" "$content" "$button1_text" "$complete_action"
  else
    termux-notification \
      "${channel_args[@]}" \
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

while IFS=$'\t' read -r bucket notification_id uuid title content task_action task_button started_value fingerprint; do
  if [[ -n "$PROMOTE_UUID" && "$uuid" == "$PROMOTE_UUID" ]]; then
    promoted_record="$bucket"$'\t'"$notification_id"$'\t'"$uuid"$'\t'"$title"$'\t'"$content"$'\t'"$task_action"$'\t'"$task_button"$'\t'"$started_value"$'\t'"$fingerprint"
    continue
  fi
  post_notification_record "$bucket" "$notification_id" "$uuid" "$title" "$content" "$task_action" "$task_button" "$started_value" "$fingerprint"
done < "$records_file"

if [[ -n "$promoted_record" ]]; then
  IFS=$'\t' read -r bucket notification_id uuid title content task_action task_button started_value fingerprint <<< "$promoted_record"
  post_notification_record "$bucket" "$notification_id" "$uuid" "$title" "$content" "$task_action" "$task_button" "$started_value" "$fingerprint"
fi

if [[ "$DRY_RUN" != "1" && "$GROUP_SUMMARY_ENABLED" == "1" ]]; then
  if [[ "$window_count" -gt 0 ]]; then
    summary_channel_args=()
    if [[ "$CHANNELS_ACTIVE" == "1" ]]; then
      summary_channel_args=(--channel "$EXECUTION_NOTIFICATION_CHANNEL")
    fi
    termux-notification \
      "${summary_channel_args[@]}" \
      --id "$EXECUTION_GROUP_SUMMARY_ID" \
      --title "Taskwarrior TNT window" \
      --content "$window_count task notification(s)" \
      --group "$EXECUTION_NOTIFICATION_GROUP" \
      --alert-once \
      --priority low
  elif command -v termux-notification-remove >/dev/null 2>&1; then
    termux-notification-remove "$EXECUTION_GROUP_SUMMARY_ID" >/dev/null 2>&1 || true
  fi

  if [[ "$overdue_count" -gt 0 ]]; then
    summary_channel_args=()
    if [[ "$CHANNELS_ACTIVE" == "1" ]]; then
      summary_channel_args=(--channel "$OVERDUE_NOTIFICATION_CHANNEL")
    fi
    termux-notification \
      "${summary_channel_args[@]}" \
      --id "$OVERDUE_GROUP_SUMMARY_ID" \
      --title "Taskwarrior TNT overdue" \
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

tracked_count="$(wc -l < "$current_file")"
if [[ "$DRY_RUN" != "1" ]]; then
  mv "$current_file" "$STATE_FILE"
fi

echo "Tracked $tracked_count Taskwarrior notification(s)."
