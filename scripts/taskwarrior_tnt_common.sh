#!/data/data/com.termux/files/usr/bin/bash

# Shared state coordination for Taskwarrior TNT scripts.
# shellcheck disable=SC2034
# These variables form the sourced helper API used by caller scripts.

TNT_LOCK_OWNED=0
TNT_LOCK_DIR=""
TNT_TASK_STATUS=""
TNT_TASK_START_EPOCH=""
TNT_TASK_SNAPSHOT_ERROR=""

tnt_acquire_state_lock() {
  local state_dir="$1"
  local timeout_seconds="${2:-10}"
  local stale_seconds="${3:-60}"
  local waited=0
  local owner_pid owner_epoch now_epoch

  if [[ "${TW_STATE_LOCK_HELD:-0}" == "1" ]]; then
    return 0
  fi

  mkdir -p "$state_dir"
  TNT_LOCK_DIR="$state_dir/.state.lock"

  while ! mkdir "$TNT_LOCK_DIR" 2>/dev/null; do
    owner_pid=""
    owner_epoch=""
    if [[ -f "$TNT_LOCK_DIR/pid" ]]; then
      IFS= read -r owner_pid < "$TNT_LOCK_DIR/pid" || true
    fi
    if [[ -f "$TNT_LOCK_DIR/epoch" ]]; then
      IFS= read -r owner_epoch < "$TNT_LOCK_DIR/epoch" || true
    fi
    now_epoch="$(date +%s)"

    if [[ "$owner_pid" =~ ^[0-9]+$ ]]; then
      if ! kill -0 "$owner_pid" 2>/dev/null; then
        rm -rf "$TNT_LOCK_DIR" 2>/dev/null || true
        continue
      fi
    elif [[ "$owner_epoch" =~ ^[0-9]+$ ]] && (( now_epoch - owner_epoch > stale_seconds )); then
      rm -rf "$TNT_LOCK_DIR" 2>/dev/null || true
      continue
    fi
    if (( waited >= timeout_seconds * 10 )); then
      echo "ERROR: timed out waiting for Taskwarrior TNT state lock" >&2
      return 1
    fi
    sleep 0.1
    waited=$((waited + 1))
  done

  printf '%s\n' "$$" > "$TNT_LOCK_DIR/pid"
  date +%s > "$TNT_LOCK_DIR/epoch"
  TNT_LOCK_OWNED=1
  export TW_STATE_LOCK_HELD=1
}

tnt_release_state_lock() {
  if [[ "$TNT_LOCK_OWNED" == "1" && -n "$TNT_LOCK_DIR" ]]; then
    rm -rf "$TNT_LOCK_DIR" 2>/dev/null || true
  fi
  TNT_LOCK_OWNED=0
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

  IFS=$'\t' read -r TNT_TASK_STATUS TNT_TASK_START_EPOCH <<< "$parsed"
  [[ -n "$TNT_TASK_STATUS" ]] || TNT_TASK_STATUS="unknown"
}
