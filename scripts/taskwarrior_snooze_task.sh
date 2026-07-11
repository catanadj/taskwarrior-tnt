#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

# Snoozes a Taskwarrior notification.

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

for config_name in TASK_BIN TW_STATE_DIR TW_FORGET_SCRIPT TW_SNOOZE_1H_MODE TW_SNOOZE_TOMORROW_MODE TW_COMMON_SCRIPT TW_ACTION_LOG_FILE TW_ACTION_TOAST_ENABLED; do
  remember_override "$config_name"
done

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
fi

for config_name in TASK_BIN TW_STATE_DIR TW_FORGET_SCRIPT TW_SNOOZE_1H_MODE TW_SNOOZE_TOMORROW_MODE TW_COMMON_SCRIPT TW_ACTION_LOG_FILE TW_ACTION_TOAST_ENABLED; do
  restore_override "$config_name"
done

TASK_UUID="${1:-}"
NOTIFICATION_ID="${2:-}"
SNOOZE_UNTIL="${3:-+1 hour}"
TASK_BIN="${TASK_BIN:-task}"
STATE_DIR="${TW_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/taskwarrior-tnt}"
SNOOZE_FILE="$STATE_DIR/snoozed-tasks"
FORGET_SCRIPT="${TW_FORGET_SCRIPT:-$HOME/.termux/tasker/taskwarrior_forget_notification.sh}"
COMMON_SCRIPT="${TW_COMMON_SCRIPT:-$(dirname "$0")/taskwarrior_tnt_common.sh}"
ACTION_LOG_FILE="${TW_ACTION_LOG_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/taskwarrior-tnt/action.log}"
ACTION_TOAST_ENABLED="${TW_ACTION_TOAST_ENABLED:-1}"

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

if [[ -z "$TASK_UUID" ]]; then
  echo "ERROR: missing task UUID"
  exit 2
fi

log_action "snooze invoked uuid=$TASK_UUID value=$SNOOZE_UNTIL task_bin=$TASK_BIN home=$HOME"

if ! command -v "$TASK_BIN" >/dev/null 2>&1; then
  log_action "ERROR task command not found: $TASK_BIN"
  show_toast "Snooze failed; task command missing"
  echo "ERROR: task command not found"
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  log_action "ERROR python3 command not found"
  show_toast "${TASK_UUID%%-*} snooze failed; python missing"
  echo "ERROR: python3 command not found"
  exit 2
fi

mkdir -p "$STATE_DIR"
tnt_acquire_state_lock "$STATE_DIR"
trap tnt_release_state_lock EXIT

remove_local_snooze() {
  tnt_remove_snooze_uuid "$SNOOZE_FILE" "$TASK_UUID"
}

remove_notification() {
  if [[ -n "$NOTIFICATION_ID" ]] && command -v termux-notification-remove >/dev/null 2>&1; then
    termux-notification-remove "$NOTIFICATION_ID" >/dev/null 2>&1 || true
  fi

  if [[ -n "$NOTIFICATION_ID" && -x "$FORGET_SCRIPT" ]]; then
    "$FORGET_SCRIPT" "$NOTIFICATION_ID" >/dev/null 2>&1 || true
  fi
}

snooze_value="$(printf '%s' "$SNOOZE_UNTIL" | tr '[:upper:]' '[:lower:]')"
snooze_mode="local"
due_modifier=""

case "$snooze_value" in
  tomorrow|"+1 day"|"1 day")
    snooze_mode="${TW_SNOOZE_TOMORROW_MODE:-modify_due}"
    due_modifier="due:due+1d"
    ;;
  "+1 hour"|"1 hour"|"1h")
    snooze_mode="${TW_SNOOZE_1H_MODE:-local}"
    due_modifier="due:due+1h"
    ;;
esac

if [[ "$snooze_mode" != "local" && "$snooze_mode" != "modify_due" ]]; then
  echo "ERROR: unsupported snooze mode: $snooze_mode"
  exit 2
fi

if [[ "$snooze_mode" == "modify_due" ]]; then
  if [[ -z "$due_modifier" ]]; then
    echo "ERROR: cannot modify due date for unsupported snooze value: $SNOOZE_UNTIL"
    exit 2
  fi

  if output="$("$TASK_BIN" rc.hooks:off rc.confirmation:no "$TASK_UUID" modify "$due_modifier" 2>&1)"; then
    log_action "OK task snooze modify uuid=$TASK_UUID modifier=$due_modifier output=$output"
  else
    rc=$?
    log_action "ERROR task snooze modify failed rc=$rc uuid=$TASK_UUID modifier=$due_modifier output=$output"
    show_toast "${TASK_UUID%%-*} snooze failed"
    echo "ERROR: task snooze failed: $output"
    exit "$rc"
  fi
  remove_local_snooze
  remove_notification

  if command -v termux-toast >/dev/null 2>&1; then
    show_toast "${TASK_UUID%%-*} moved to tomorrow"
  fi
  exit 0
fi

until_epoch="$(python3 - "$SNOOZE_UNTIL" <<'PY'
import sys
from datetime import datetime, timedelta

value = sys.argv[1].strip().lower()
now = datetime.now().astimezone()

if value in ("tomorrow", "+1 day", "1 day"):
    target = now + timedelta(days=1)
elif value in ("+1 hour", "1 hour", "1h"):
    target = now + timedelta(hours=1)
elif value.endswith("h") and value[:-1].replace(".", "", 1).isdigit():
    target = now + timedelta(hours=float(value[:-1]))
elif value.endswith("m") and value[:-1].replace(".", "", 1).isdigit():
    target = now + timedelta(minutes=float(value[:-1]))
else:
    raise SystemExit(f"unsupported snooze value: {value}")

print(int(target.timestamp()))
PY
)"

remove_local_snooze
printf '%s\t%s\n' "$TASK_UUID" "$until_epoch" >> "$SNOOZE_FILE"

remove_notification

show_toast "${TASK_UUID%%-*} snoozed"
