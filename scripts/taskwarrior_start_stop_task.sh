#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

# Starts or stops a Taskwarrior task from a notification action.

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

for config_name in TASK_BIN TW_NOTIFY_SCRIPT TW_JOT_TIMELOG_ENABLED JOT_BIN JOT_RUNNER TW_ACTION_LOG_FILE TW_ACTION_TOAST_ENABLED TW_PROMOTE_STARTED_ON_START TW_COMMON_SCRIPT TW_STATE_DIR; do
  remember_override "$config_name"
done

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
fi

for config_name in TASK_BIN TW_NOTIFY_SCRIPT TW_JOT_TIMELOG_ENABLED JOT_BIN JOT_RUNNER TW_ACTION_LOG_FILE TW_ACTION_TOAST_ENABLED TW_PROMOTE_STARTED_ON_START TW_COMMON_SCRIPT TW_STATE_DIR; do
  restore_override "$config_name"
done

ACTION="${1:-}"
TASK_UUID="${2:-}"
TASK_BIN="${TASK_BIN:-task}"
NOTIFY_SCRIPT="${TW_NOTIFY_SCRIPT:-$HOME/.termux/tasker/taskwarrior_notify_due_tasks.sh}"
JOT_TIMELOG_ENABLED="${TW_JOT_TIMELOG_ENABLED:-1}"
JOT_BIN="${JOT_BIN:-jot}"
JOT_RUNNER="${JOT_RUNNER:-}"
ACTION_LOG_FILE="${TW_ACTION_LOG_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/taskwarrior-tnt/action.log}"
ACTION_TOAST_ENABLED="${TW_ACTION_TOAST_ENABLED:-1}"
PROMOTE_STARTED_ON_START="${TW_PROMOTE_STARTED_ON_START:-1}"
COMMON_SCRIPT="${TW_COMMON_SCRIPT:-$(dirname "$0")/taskwarrior_tnt_common.sh}"
STATE_DIR="${TW_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/taskwarrior-tnt}"
JOT_STATUS="off"
TASK_SHORT_ID="${TASK_UUID%%-*}"
ACTIVE_STARTED_EPOCH=""
ACTIVE_DURATION=""

export HOME="${HOME:-/data/data/com.termux/files/home}"
export PATH="/data/data/com.termux/files/usr/bin:/data/data/com.termux/files/usr/bin/applets:${PATH:-}"

if [[ ! -r "$COMMON_SCRIPT" ]]; then
  echo "ERROR: shared helper is missing: $COMMON_SCRIPT"
  exit 2
fi
# shellcheck source=/dev/null
source "$COMMON_SCRIPT"

log_action() {
  mkdir -p "$(dirname "$ACTION_LOG_FILE")" 2>/dev/null || true
  { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$ACTION_LOG_FILE"; } 2>/dev/null || true
}

show_toast() {
  if [[ "$ACTION_TOAST_ENABLED" == "1" ]] && command -v termux-toast >/dev/null 2>&1; then
    termux-toast "$1" >/dev/null 2>&1 || true
  fi
}

run_jot_command() {
  local action="$1"
  local first_line=""
  local output

  if [[ -n "$JOT_RUNNER" ]]; then
    "$JOT_RUNNER" "$JOT_BIN" timelog "$action" "$TASK_UUID"
    return $?
  fi

  if [[ -f "$JOT_BIN" ]]; then
    IFS= read -r first_line < "$JOT_BIN" || true
  fi

  case "$first_line" in
    "#!/usr/bin/env python3"*|"#!/usr/bin/env python"*)
      python3 "$JOT_BIN" timelog "$action" "$TASK_UUID"
      ;;
    "#!/usr/bin/env bash"*)
      bash "$JOT_BIN" timelog "$action" "$TASK_UUID"
      ;;
    "#!/usr/bin/env sh"*)
      sh "$JOT_BIN" timelog "$action" "$TASK_UUID"
      ;;
    *)
      "$JOT_BIN" timelog "$action" "$TASK_UUID"
      ;;
  esac
}

task_start_epoch() {
  local output
  if output="$("$TASK_BIN" rc.hooks:off rc.verbose:nothing rc.json.array:on "$TASK_UUID" export 2>/dev/null)"; then
    python3 - "$output" <<'PY'
import json
import sys
from datetime import datetime, timezone

try:
    tasks = json.loads(sys.argv[1] or "[]")
except json.JSONDecodeError:
    raise SystemExit(1)

if not tasks:
    raise SystemExit(1)

start = tasks[0].get("start")
if not start:
    raise SystemExit(1)

for fmt in ("%Y%m%dT%H%M%SZ", "%Y%m%dT%H%M%S"):
    try:
        parsed = datetime.strptime(start, fmt)
    except ValueError:
        continue
    if start.endswith("Z"):
        parsed = parsed.replace(tzinfo=timezone.utc).astimezone()
    else:
        parsed = parsed.astimezone()
    print(int(parsed.timestamp()))
    raise SystemExit(0)

raise SystemExit(1)
PY
  else
    return 1
  fi
}

format_duration() {
  python3 - "$1" <<'PY'
import sys
import time

try:
    seconds = max(0, int(time.time()) - int(sys.argv[1]))
except (IndexError, ValueError):
    raise SystemExit(1)

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
print(" ".join(parts) if parts else "0m")
PY
}

if [[ -z "$ACTION" || -z "$TASK_UUID" ]]; then
  echo "ERROR: usage: taskwarrior_start_stop_task.sh start|stop <uuid>"
  exit 2
fi

log_action "start_stop invoked action=$ACTION uuid=$TASK_UUID task_bin=$TASK_BIN jot_bin=$JOT_BIN home=$HOME"

if ! command -v "$TASK_BIN" >/dev/null 2>&1; then
  show_toast "$TASK_SHORT_ID $ACTION failed; task command missing"
  echo "ERROR: task command not found"
  exit 2
fi

tnt_acquire_state_lock "$STATE_DIR"
trap tnt_release_state_lock EXIT

run_task_action() {
  local action="$1"
  local output rc
  if output="$("$TASK_BIN" rc.hooks:off rc.confirmation:no "$TASK_UUID" "$action" 2>&1)"; then
    log_action "OK task $action uuid=$TASK_UUID output=$output"
    return 0
  else
    rc=$?
    log_action "ERROR task $action failed rc=$rc uuid=$TASK_UUID output=$output"
    show_toast "$TASK_SHORT_ID $action failed"
    echo "ERROR: task $action failed: $output"
    return "$rc"
  fi
}

run_jot_timelog() {
  local action="$1"
  if [[ "$JOT_TIMELOG_ENABLED" != "1" ]]; then
    JOT_STATUS="disabled"
    return 0
  fi
  if ! command -v "$JOT_BIN" >/dev/null 2>&1; then
    log_action "WARN jot command not found: $JOT_BIN"
    echo "WARN: jot command not found"
    JOT_STATUS="missing"
    return 0
  fi
  local output
  if output="$(run_jot_command "$action" 2>&1)"; then
    log_action "OK jot timelog $action uuid=$TASK_UUID output=$output"
    JOT_STATUS="ok"
  else
    local rc=$?
    log_action "WARN jot timelog $action failed rc=$rc output=$output"
    echo "WARN: jot timelog $action failed"
    JOT_STATUS="failed"
  fi
}

case "$ACTION" in
  start)
    run_task_action start
    run_jot_timelog start
    message="Task started"
    ;;
  stop)
    if ACTIVE_STARTED_EPOCH="$(task_start_epoch)"; then
      ACTIVE_DURATION="$(format_duration "$ACTIVE_STARTED_EPOCH" 2>/dev/null || true)"
    else
      ACTIVE_STARTED_EPOCH=""
    fi
    run_task_action stop
    run_jot_timelog stop
    message="Task stopped"
    ;;
  *)
    echo "ERROR: unsupported action: $ACTION"
    exit 2
    ;;
esac

if command -v termux-toast >/dev/null 2>&1; then
  toast_message="$TASK_SHORT_ID $ACTION"
  if [[ "$ACTION" == "stop" && -n "$ACTIVE_DURATION" ]]; then
    toast_message="$toast_message; active $ACTIVE_DURATION"
  fi
  case "$JOT_STATUS" in
    failed|missing)
      show_toast "$toast_message; jot $JOT_STATUS"
      ;;
    *)
      show_toast "$toast_message"
      ;;
  esac
fi

tnt_release_state_lock

if [[ -x "$NOTIFY_SCRIPT" ]]; then
  if [[ "$ACTION" == "start" && "$PROMOTE_STARTED_ON_START" == "1" ]]; then
    TW_PROMOTE_UUID="$TASK_UUID" "$NOTIFY_SCRIPT" >/dev/null 2>&1 || true
  else
    "$NOTIFY_SCRIPT" >/dev/null 2>&1 || true
  fi
fi
