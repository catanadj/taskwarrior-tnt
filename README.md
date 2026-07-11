# Taskwarrior TNT

Taskwarrior TNT means Termux Notifications through Tasker: scripts for showing Taskwarrior tasks due near the current time. The main mode posts one Android notification per task, with actions for `Start`/`Stop`, `Done`, and `Tomorrow`.

By default, pending tasks due from the last 2 hours through the next 2 hours are shown.

## Files

- `taskwarrior_notify_due_tasks.sh`: posts per-task Android notifications.
- `taskwarrior_start_stop_task.sh`: runs `task <uuid> start|stop` from a notification.
- `taskwarrior_complete_task.sh`: completes a task from the `Done` button.
- `taskwarrior_snooze_task.sh`: handles local snooze and tomorrow actions.
- `taskwarrior_forget_notification.sh`: updates state when a notification is dismissed.
- `taskwarrior_tnt_common.sh`: shared state locking and atomic update helpers.
- `taskwarrior_gui.sh`: optional Termux:GUI dashboard.
- `taskwarrior_tasker.conf`: config file copied to `~/.termux/tasker/`.

## Install

Install Termux packages:

```sh
pkg install taskwarrior python termux-api
pip install termuxgui
```

Install the Termux:API Android app. Install Termux:GUI too if you want the optional dashboard.

Run the installer:

```sh
chmod +x install.sh
./install.sh
```

The installer copies scripts to `~/.termux/tasker`, preserves your existing config, writes the latest config as `taskwarrior_tasker.conf.example`, sets permissions, and runs basic checks.

Useful tests:

```sh
~/.termux/tasker/taskwarrior_notify_due_tasks.sh --doctor
~/.termux/tasker/taskwarrior_notify_due_tasks.sh --test-notification
TW_DRY_RUN=1 ~/.termux/tasker/taskwarrior_notify_due_tasks.sh
```

Launch the optional GUI:

```sh
~/.termux/tasker/taskwarrior_gui.sh
```

## Tasker Setup

Create a scheduled Tasker profile, for example every 15 or 30 minutes. In the attached task:

1. Add a `Termux:Tasker` action.
2. Set `Executable` to `taskwarrior_notify_due_tasks.sh`.
3. Disable `Execute in a terminal session`.
4. Enable `Wait for result for commands`.
5. Use a timeout above zero, for example `10s`.

No separate Tasker `Notify` action is needed. The script posts notifications directly through Termux:API.

For the GUI dashboard, create a separate Tasker task or launcher shortcut for `taskwarrior_gui.sh`.

## Configuration

Edit:

```sh
nano ~/.termux/tasker/taskwarrior_tasker.conf
```

Common settings:

```sh
TW_WINDOW_PAST_HOURS=2
TW_WINDOW_FUTURE_HOURS=2
TW_MAX_TASKS=12
TW_REORDER_EACH_RUN=0

TW_QUIET_HOURS_ENABLED=0
TW_QUIET_HOURS_START=22:00
TW_QUIET_HOURS_END=07:00

TW_EXECUTION_NOTIFICATION_ICON=event_note
TW_OVERDUE_NOTIFICATION_ICON=warning
TW_STARTED_NOTIFICATION_ICON=play_arrow
TW_NOTIFICATION_PRIORITY=high
TW_STARTED_NOTIFICATION_PRIORITY=high
TW_PROMOTE_STARTED_ON_START=1

TW_START_STOP_ACTION_ENABLED=1
TW_SNOOZE_1H_MODE=local
TW_SNOOZE_TOMORROW_MODE=modify_due

TW_JOT_TIMELOG_ENABLED=1
JOT_BIN=/data/data/com.termux/files/usr/bin/jot
JOT_RUNNER=
TW_ACTION_TOAST_ENABLED=1
```

Notes:

- `TW_REORDER_EACH_RUN=1` removes and reposts all matching notifications each scan so Android's recency ordering is refreshed. This can cause visible refreshes or sounds.
- `TW_PROMOTE_STARTED_ON_START=1` only promotes the task you just started. It removes that task notification and posts it after the normal scan order so Android usually places it on top.
- Quiet hours skip notification posting but still let the scan run.
- Active tasks and execution-window tasks take precedence over overdue tasks when `TW_MAX_TASKS` is reached.
- `TW_SNOOZE_TOMORROW_MODE=modify_due` runs `task <uuid> modify due:due+1d`.
- One-off environment variables override the config, for example `TW_DRY_RUN=1`.

## Behavior

Tasks are included when they are pending, have a `due` value, and are due today before the future-window end. They are split into:

- execution window: due from `now - TW_WINDOW_PAST_HOURS` through `now + TW_WINDOW_FUTURE_HOURS`
- overdue: due today but before the execution window

Notification title format:

```text
05:50 - 06:00 | Task description
```

If a task has a `duration` UDA such as `PT10M`, the displayed range is `due - duration` through `due`. Without duration, the title uses `Due HH:MM`.

Notification content starts with one of `OVERDUE`, `SOON`, `NOW`, or `DUE`. Started tasks use `ACTIVE` instead. The content also includes the time delta and optional project/tags.

Actions:

- `Start` / `Stop`: runs Taskwarrior tracking and optional `jot timelog start|stop <uuid>`.
- `Done`: completes the task, removes its notification, and stops jot timelog if the task was active.
- `Tomorrow`: moves the due date to tomorrow by default.

Each notification uses a stable Android notification ID derived from the Taskwarrior UUID. TNT stores a locked state manifest and only calls Android when displayed task data changes. Swiped notifications are removed from the manifest and return on the next scan if still relevant.

## Jot Integration

When enabled, notification actions also run:

```sh
jot timelog start <uuid>
jot timelog stop <uuid>
```

Action scripts log to:

```sh
~/.local/state/taskwarrior-tnt/action.log
```

Toasts show short results such as `<uuid-prefix> start` or `<uuid-prefix> completed`. Failed Taskwarrior actions are logged and produce a failure toast. Jot is mentioned only when it is missing or fails.

If `jot` has a `/usr/bin/env` shebang that fails from Android notification actions, the scripts auto-detect common `python3`, `bash`, and `sh` shebangs. You can force a runner:

```sh
JOT_RUNNER=python3
```

## Troubleshooting

Run:

```sh
~/.termux/tasker/taskwarrior_notify_due_tasks.sh --doctor
```

If no notifications appear, test Termux:API directly:

```sh
~/.termux/tasker/taskwarrior_notify_due_tasks.sh --test-notification
```

If that fails, check Android notification permission for Termux:API.

If the test notification works, check whether Taskwarrior returns matching tasks:

```sh
TW_DRY_RUN=1 ~/.termux/tasker/taskwarrior_notify_due_tasks.sh
```

`DRY_RUN` lines mean matching tasks were found. `Posted 0 Taskwarrior notification(s).` means no pending tasks have a `due` timestamp inside the configured window.

Installer options:

```sh
TW_INSTALL_FORCE_CONFIG=1 ./install.sh
TW_INSTALL_RUN_CHECKS=0 ./install.sh
TW_INSTALL_DIR=/path/to/tasker ./install.sh
```

`TW_INSTALL_FORCE_CONFIG=1` overwrites the installed config. Without it, the installer preserves your current config.
