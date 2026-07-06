#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

# Installs Taskwarrior TNT scripts into Termux:Tasker.

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${TW_INSTALL_DIR:-$HOME/.termux/tasker}"
CONFIG_FILE="$INSTALL_DIR/taskwarrior_tasker.conf"
CONFIG_EXAMPLE="$SOURCE_DIR/scripts/taskwarrior_tasker.conf"
FORCE_CONFIG="${TW_INSTALL_FORCE_CONFIG:-0}"
RUN_CHECKS="${TW_INSTALL_RUN_CHECKS:-1}"

required_files=(
  taskwarrior_window_reminders.sh
  taskwarrior_notify_due_tasks.sh
  taskwarrior_complete_task.sh
  taskwarrior_forget_notification.sh
  taskwarrior_snooze_task.sh
  taskwarrior_start_stop_task.sh
  taskwarrior_gui.sh
  taskwarrior_gui.py
)

if [[ ! -d "$SOURCE_DIR/scripts" ]]; then
  echo "ERROR: scripts directory not found: $SOURCE_DIR/scripts"
  exit 2
fi

mkdir -p "$INSTALL_DIR"

for file in "${required_files[@]}"; do
  if [[ ! -f "$SOURCE_DIR/scripts/$file" ]]; then
    echo "ERROR: missing source file: scripts/$file"
    exit 2
  fi
  cp "$SOURCE_DIR/scripts/$file" "$INSTALL_DIR/$file"
  chmod 700 "$INSTALL_DIR/$file"
done

if [[ "$FORCE_CONFIG" == "1" || ! -f "$CONFIG_FILE" ]]; then
  cp "$CONFIG_EXAMPLE" "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
  echo "Installed config: $CONFIG_FILE"
else
  cp "$CONFIG_EXAMPLE" "$CONFIG_FILE.example"
  chmod 600 "$CONFIG_FILE.example"
  echo "Kept existing config: $CONFIG_FILE"
  echo "Wrote latest example: $CONFIG_FILE.example"
fi

chmod 700 "$HOME/.termux" "$INSTALL_DIR" 2>/dev/null || true

if [[ "$RUN_CHECKS" == "1" ]]; then
  echo
  echo "Running checks..."

  for command_name in task python3; do
    if command -v "$command_name" >/dev/null 2>&1; then
      echo "OK: $command_name found"
    else
      echo "WARN: $command_name not found"
    fi
  done

  if command -v termux-notification >/dev/null 2>&1; then
    echo "OK: termux-notification found"
  else
    echo "WARN: termux-notification not found. Install Termux:API app and run: pkg install termux-api"
  fi

  if python3 -c 'import termuxgui' >/dev/null 2>&1; then
    echo "OK: termuxgui python module found"
  else
    echo "WARN: termuxgui python module not found. Install Termux:GUI app and run: pip install termuxgui"
  fi

  for file in "${required_files[@]}"; do
    case "$file" in
      *.sh)
        bash -n "$INSTALL_DIR/$file"
        ;;
      *.py)
        python3 -m py_compile "$INSTALL_DIR/$file"
        ;;
    esac
  done
  bash -n "$CONFIG_FILE"
  echo "OK: syntax checks passed"
fi

cat <<EOF

Installed to:
  $INSTALL_DIR

Tasker executable:
  taskwarrior_notify_due_tasks.sh

GUI executable:
  taskwarrior_gui.sh

Edit config:
  nano $CONFIG_FILE

Test scan:
  $INSTALL_DIR/taskwarrior_notify_due_tasks.sh
EOF
