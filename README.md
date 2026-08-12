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

Run the local dependency-free regression suite from the repository root:

```bash
PYTHONPATH=. python3 -m unittest discover -s tests -v
```

```sh
~/.termux/tasker/taskwarrior_notify_due_tasks.sh --doctor
~/.termux/tasker/taskwarrior_notify_due_tasks.sh --setup-channels
~/.termux/tasker/taskwarrior_notify_due_tasks.sh --test-notification
TW_DRY_RUN=1 ~/.termux/tasker/taskwarrior_notify_due_tasks.sh
```

Tools that sync Taskwarrior can request an immediate live refresh with:

```sh
~/.termux/tasker/tnt refresh
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
5. Use a timeout above zero, for example `10s`. When pre-scan sync is enabled,
   set it above `TW_SYNC_TIMEOUT_SECONDS`, for example `330s` for the default.

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
TW_ALWAYS_SHOW_ACTIVE=0
TW_COMMAND_TIMEOUT_SECONDS=30

TW_SYNC_BEFORE_SCAN_ENABLED=0
TW_SYNC_SCRIPT="/path/to/taskwarrior-sync-helper/task_sync.sh"
TW_SYNC_TIMEOUT_SECONDS=300

# Optional eligibility rules. Lists are comma-separated.
TW_TASK_FILTER=""
TW_INCLUDE_PROJECTS=""
TW_EXCLUDE_PROJECTS=""
TW_INCLUDE_TAGS=""
TW_EXCLUDE_TAGS=""
TW_OPTOUT_TAG=""

TW_QUIET_HOURS_ENABLED=0
TW_QUIET_HOURS_START=22:00
TW_QUIET_HOURS_END=07:00

TW_EXECUTION_NOTIFICATION_ICON=event_note
TW_OVERDUE_NOTIFICATION_ICON=warning
TW_STARTED_NOTIFICATION_ICON=play_arrow
TW_NOTIFICATION_CHANNELS_ENABLED=1
TW_EXECUTION_NOTIFICATION_CHANNEL=taskwarrior-tnt-window
TW_OVERDUE_NOTIFICATION_CHANNEL=taskwarrior-tnt-overdue
TW_STARTED_NOTIFICATION_CHANNEL=taskwarrior-tnt-active
TW_NOTIFICATION_PRIORITY=high
TW_STARTED_NOTIFICATION_ONGOING=0
TW_NAUTICAL_PROGRESS_ENABLED=1
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

When pre-scan sync is enabled, TNT runs the configured helper before reading
Taskwarrior and before acquiring its notification-state lock. Output is written
to `pre-scan-sync.log` under `TW_STATE_DIR`. A failed or timed-out sync is
reported, but TNT continues with local task data so reminders remain available
during network outages. Dry runs and diagnostic commands do not trigger sync.

Notes:

- `TW_REORDER_EACH_RUN=1` removes and reposts all matching notifications each scan so Android's recency ordering is refreshed. This can cause visible refreshes or sounds.
- `TW_PROMOTE_STARTED_ON_START=1` only promotes the task you just started. It removes that task notification and posts it after the normal scan order so Android usually places it on top.
- Quiet hours skip notification posting but still let the scan run.
- On Android 8+, window, overdue, and active tasks use separate notification channels.
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

Actions inspect the current Taskwarrior state before changing it. Already-completed or missing tasks are acknowledged and their stale notifications are cleared. Repeated Start or Stop actions also succeed harmlessly when the task is already in the requested state.

Each notification uses a stable Android notification ID derived from the Taskwarrior UUID. TNT stores a locked state manifest and only calls Android when displayed task data changes. Swiped notifications are removed from the manifest and return on the next scan if still relevant.

## Hookless Actions and Deferred Reconciliation

TNT deliberately invokes Taskwarrior with hooks disabled. Tasker launches Termux
actions in a reduced Android environment where hook dependencies, interpreter
paths, and environment variables may not match an interactive Termux shell.
Keeping notification actions hookless makes `Start`, `Stop`, `Done`, and
`Tomorrow` reliable and prevents every edge client from having to reproduce the
full hook environment.

Integrations that would normally depend on hooks are handled at explicit,
controlled boundaries:

- TNT invokes Jot timelog commands directly for `Start`, `Stop`, and `Done`.
- Nautical recurrence is recovered by `taskwarrior-sync-helper` in an environment
  where Nautical is installed and configured.

The Nautical flow is eventually consistent:

1. TNT changes the task locally with hooks disabled.
2. `taskwarrior-sync-helper` detects the Taskwarrior local-operation backlog.
3. Nautical reconciliation runs before uploading local changes, creating any
   missing successor tasks.
4. The original change and its successor are uploaded together.
5. When a device instead pulls a hookless completion, reconciliation runs after
   the pull. If it creates local operations, Sync Helper performs one immediate
   follow-up sync so the successors are propagated in the same invocation.

Enable applied reconciliation in the local Sync Helper configuration on the
device responsible for recovery:

```sh
RUN_NAUTICAL_RECONCILE=1
NAUTICAL_RECONCILE_APPLY=1
```

Run `taskwarrior-sync-helper/task_sync.sh` on the normal sync schedule rather
than calling `task sync` directly. Until that helper completes successfully, a
successor for a hooklessly completed recurring task may not yet exist. A failed
reconciliation exits nonzero without acknowledging the pulled signal. A failed
follow-up upload also exits nonzero and retains its pending generation. In both
cases, the next Sync Helper run retries safely.

### Notification channels

TNT creates separate channels for execution-window, overdue, and active tasks on the first real scan. This lets you configure sound, vibration, visibility, and interruption behavior for each category in Android's notification settings.

Force channel setup after changing channel IDs or names:

```sh
~/.termux/tasker/taskwarrior_notify_due_tasks.sh --setup-channels
```

Android preserves user settings for an existing channel ID. Changing only its configured name will not reset sound or vibration choices. If `termux-notification-channel` is unavailable or setup fails, TNT warns and uses Termux's default notification channel.

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
