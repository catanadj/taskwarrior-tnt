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
SCRIPT_DIR="$(dirname "$0")"
export PYTHONPATH="$SCRIPT_DIR${PYTHONPATH:+:$PYTHONPATH}"

if ! command -v "$TASK_BIN" >/dev/null 2>&1; then
  echo "ERROR: task command not found. Install Taskwarrior in Termux first."
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 command not found. Install Python in Termux first."
  exit 2
fi

python3 -m taskwarrior_tnt.legacy_window \
  "$WINDOW_PAST_HOURS" "$WINDOW_FUTURE_HOURS" "$MAX_TASKS"
