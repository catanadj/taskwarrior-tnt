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

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
fi

restore_override TW_STATE_DIR

NOTIFICATION_ID="${1:-}"
STATE_DIR="${TW_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/taskwarrior-tnt}"
STATE_FILE="$STATE_DIR/active-notifications"

if [[ -z "$NOTIFICATION_ID" || ! -f "$STATE_FILE" ]]; then
  exit 0
fi

tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file"' EXIT

while IFS= read -r active_id; do
  [[ "$active_id" == "$NOTIFICATION_ID" ]] && continue
  [[ -n "$active_id" ]] && printf '%s\n' "$active_id" >> "$tmp_file"
done < "$STATE_FILE"

mv "$tmp_file" "$STATE_FILE"
trap - EXIT
