#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

# Removes a notification id from the scan script's active-notification state.

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

remember_override TW_STATE_DIR
remember_override TW_COMMON_SCRIPT

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
fi

restore_override TW_STATE_DIR
restore_override TW_COMMON_SCRIPT

NOTIFICATION_ID="${1:-}"
STATE_DIR="${TW_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/taskwarrior-tnt}"
STATE_FILE="$STATE_DIR/active-notifications"
COMMON_SCRIPT="${TW_COMMON_SCRIPT:-$(dirname "$0")/taskwarrior_tnt_common.sh}"

if [[ -z "$NOTIFICATION_ID" || ! -f "$STATE_FILE" ]]; then
  exit 0
fi

if [[ ! -r "$COMMON_SCRIPT" ]]; then
  echo "ERROR: shared helper is missing: $COMMON_SCRIPT"
  exit 2
fi
# shellcheck source=/dev/null
source "$COMMON_SCRIPT"

tnt_acquire_state_lock "$STATE_DIR"
trap tnt_release_state_lock EXIT
tnt_remove_manifest_id "$STATE_FILE" "$NOTIFICATION_ID"
