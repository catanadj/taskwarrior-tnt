#!/data/data/com.termux/files/usr/bin/bash

# Shared state coordination for Taskwarrior TNT scripts.
# shellcheck disable=SC2034
# These variables form the sourced helper API used by caller scripts.

TNT_TASK_STATUS=""
TNT_TASK_START_EPOCH=""
TNT_TASK_SNAPSHOT_ERROR=""
TNT_STATE_LOCK_FD=""

tnt_flock_available() {
  local version
  command -v flock >/dev/null 2>&1 || return 1
  version="$(flock --version 2>/dev/null)" || return 1
  [[ "$version" == *"util-linux"* ]]
}

tnt_acquire_state_lock() {
  local state_dir="$1"
  local timeout_seconds="${2:-10}"
  local lock_file rc

  if [[ "${TW_STATE_LOCK_HELD:-0}" == "1" ]]; then
    return 0
  fi

  if ! tnt_flock_available; then
    echo "ERROR: util-linux flock is required; install it with: pkg install util-linux" >&2
    return 127
  fi
  if [[ ! "$timeout_seconds" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    echo "ERROR: state lock timeout must be a non-negative number of seconds" >&2
    return 2
  fi
  if ! mkdir -p "$state_dir"; then
    echo "ERROR: cannot create state directory: $state_dir" >&2
    return 2
  fi

  lock_file="$state_dir/.state.lockfile"
  if ! (umask 077; : >> "$lock_file") || ! chmod 600 "$lock_file"; then
    echo "ERROR: cannot create state lock file: $lock_file" >&2
    return 2
  fi

  if ! { exec {TNT_STATE_LOCK_FD}>>"$lock_file"; }; then
    echo "ERROR: cannot open state lock file: $lock_file" >&2
    return 2
  fi
  chmod 600 "$lock_file" || {
    exec {TNT_STATE_LOCK_FD}>&-
    TNT_STATE_LOCK_FD=""
    echo "ERROR: cannot set state lock file permissions: $lock_file" >&2
    return 2
  }

  if flock -E 75 -w "$timeout_seconds" "$TNT_STATE_LOCK_FD"; then
    export TW_STATE_LOCK_HELD=1
    return 0
  else
    rc=$?
  fi
  exec {TNT_STATE_LOCK_FD}>&-
  TNT_STATE_LOCK_FD=""
  if (( rc == 75 )); then
    echo "ERROR: timed out waiting for Taskwarrior TNT state lock" >&2
  fi
  return "$rc"
}

tnt_release_state_lock() {
  if [[ -n "$TNT_STATE_LOCK_FD" ]]; then
    flock -u "$TNT_STATE_LOCK_FD" || true
    exec {TNT_STATE_LOCK_FD}>&-
    TNT_STATE_LOCK_FD=""
  fi
  unset TW_STATE_LOCK_HELD
}

tnt_remove_manifest_id() {
  local state_file="$1"
  local notification_id="$2"
  local tmp_file

  [[ -z "$notification_id" || ! -f "$state_file" ]] && return 0
  tmp_file="$(mktemp)"
  while IFS=$'\t' read -r active_id remainder; do
    [[ "$active_id" == "$notification_id" ]] && continue
    if [[ -n "$active_id" ]]; then
      printf '%s' "$active_id" >> "$tmp_file"
      [[ -n "$remainder" ]] && printf '\t%s' "$remainder" >> "$tmp_file"
      printf '\n' >> "$tmp_file"
    fi
  done < "$state_file"
  mv "$tmp_file" "$state_file"
}

tnt_remove_snooze_uuid() {
  local snooze_file="$1"
  local task_uuid="$2"
  local tmp_file

  tmp_file="$(mktemp)"
  if [[ -f "$snooze_file" ]]; then
    while IFS=$'\t' read -r active_uuid active_until; do
      [[ "$active_uuid" == "$task_uuid" ]] && continue
      [[ -n "$active_uuid" && -n "$active_until" ]] &&
        printf '%s\t%s\n' "$active_uuid" "$active_until" >> "$tmp_file"
    done < "$snooze_file"
  fi
  mv "$tmp_file" "$snooze_file"
}

tnt_load_task_snapshot() {
  local task_bin="$1"
  local task_uuid="$2"
  local output parsed

  TNT_TASK_STATUS=""
  TNT_TASK_START_EPOCH=""
  TNT_TASK_SNAPSHOT_ERROR=""

  if ! output="$("$task_bin" rc.hooks:off rc.verbose:nothing rc.json.array:on "$task_uuid" export 2>&1)"; then
    TNT_TASK_SNAPSHOT_ERROR="$output"
    return 2
  fi

  if ! parsed="$(PYTHONPATH="$(dirname "$0")${PYTHONPATH:+:$PYTHONPATH}" \
      python3 -m taskwarrior_tnt.taskwarrior snapshot "$task_bin" "$task_uuid" 2>&1)"; then
    TNT_TASK_SNAPSHOT_ERROR="$parsed"
    return 2
  fi

  IFS='|' read -r TNT_TASK_STATUS TNT_TASK_START_EPOCH <<< "$parsed"
  [[ -n "$TNT_TASK_STATUS" ]] || TNT_TASK_STATUS="unknown"
}
