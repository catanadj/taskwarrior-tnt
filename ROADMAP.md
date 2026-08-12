# Taskwarrior TNT Roadmap

This checklist prioritizes work that improves both the Android experience and the internal architecture. Complete each phase in order unless a production bug requires an earlier intervention.

## Phase 0: Finish The Current Reliability Release

- [x] Add separate Android channels for execution-window, overdue, and active tasks.
- [x] Fall back to the default channel when channel setup is unavailable.
- [x] Make notification actions inspect current Taskwarrior state.
- [x] Treat already-completed and missing tasks as stale reminders rather than action failures.
- [x] Make repeated Start and Stop actions idempotent.
- [x] Pass the notification ID to Start and Stop actions for stale-reminder cleanup.
- [x] Remove generated `scripts/__pycache__/` files and add Python cache patterns to `.gitignore`.
- [x] Review the pending diff and rerun all existing verification.
- [x] Commit and push the channel and state-aware action changes.

### Completion Criteria

- [x] A stale `Done` action clears the reminder and reports that the task is already complete.
- [x] Start, Stop, Done, and Tomorrow work normally for pending tasks.
- [x] Existing installations continue to work after rerunning `install.sh`.
- [x] The repository is clean after verification.

## Phase 1: Establish An Automated Safety Net

- [x] Create a `tests/` directory and a reusable fake-command harness.
- [x] Add fixed-clock tests for reminder-window boundaries.
- [x] Test midnight and local-time-zone behavior.
- [x] Test ISO 8601 duration parsing and displayed start times.
- [x] Test active, execution-window, and overdue selection priority.
- [x] Test `TW_MAX_TASKS` behavior with a large overdue backlog.
- [x] Test quiet hours that remain within one day.
- [x] Test quiet hours that cross midnight.
- [x] Test local snooze creation and expiry.
- [x] Test tomorrow snooze due-date modification and stale snooze removal.
- [x] Test snooze replacement.
- [x] Test snooze expiry across midnight.
- [x] Test notification manifest updates and unchanged-task suppression.
- [x] Test swipe dismissal followed by restoration on the next scan.
- [x] Test completed, missing, already-active, and already-stopped action states.
- [x] Test channel creation, caching, routing, failure fallback, and recovery.
- [x] Add shell syntax and Python compilation checks.
- [x] Add `shellcheck` checks.
- [x] Add GitHub Actions to run the complete test suite.

### Completion Criteria

- [x] Tests run without Android, Tasker, Termux:API, or a real Taskwarrior database.
- [x] Time-dependent tests do not use the real clock.
- [x] Every current notification action has success, stale-state, and failure coverage.

## Phase 2: Extract A Shared Python Core

- [x] Create a `taskwarrior_tnt/` Python package.
- [x] Add typed domain models for tasks and reminders.
- [x] Move Taskwarrior export commands into `taskwarrior.py`.
- [x] Move date, duration, and delta formatting into `formatting.py` for the Python clients.
- [x] Move window filtering, bucketing, sorting, and limits into `policy.py` for the GUI and notifier.
- [x] Move notification manifest, snooze state, and locking into `state.py`.
- [x] Add typed manifest and snooze file operations in `state.py`.
- [x] Add the shared state-lock implementation in `state.py`.
- [x] Add an Android command adapter in `android.py`.
- [x] Add state-aware Start, Stop, Done, and due-modification planning in `actions.py`.
- [x] Isolate Jot support behind an integration interface.
- [x] Make the GUI consume the shared reminder-building pipeline.
- [x] Make the notifier consume the shared reminder-building pipeline.
- [x] Normalize Taskwarrior exports through typed `TaskRecord` objects for the GUI.
- [x] Retire all embedded Python heredocs from shell scripts.
- [x] Retire the notifier record-generation heredoc.
- [x] Retire the legacy window-reminder heredoc.
- [x] Retire the shared Taskwarrior snapshot-parser heredoc.
- [x] Retire the action-script duration-formatting heredocs.
- [x] Retire the snooze-deadline and quiet-hours heredocs.
- [x] Retire duplicated parsing logic from `taskwarrior_window_reminders.sh`.
- [x] Preserve current behavior through characterization tests during extraction.

### Proposed Package Layout

```text
taskwarrior_tnt/
  __init__.py
  cli.py
  config.py
  models.py
  taskwarrior.py
  policy.py
  formatting.py
  state.py
  android.py
  actions.py
  integrations.py
```

### Completion Criteria

- [x] Reminder selection has one implementation shared by notifications and the GUI.
- [x] Taskwarrior commands have one adapter with consistent hook, timeout, and error handling.
- [x] Android commands have one adapter that can be replaced by a fake during tests.
- [ ] Shell remains only where Termux:Tasker requires executable wrappers.

## Phase 3: Introduce A Unified CLI

- [x] Add a `tnt` command with stable subcommands.
- [x] Implement `tnt scan`.
- [x] Implement `tnt action start|stop|done|snooze`.
- [x] Implement `tnt channels setup`.
- [x] Implement `tnt doctor`.
- [x] Implement `tnt status`.
- [x] Implement `tnt gui`.
- [ ] Turn existing Tasker scripts into thin compatibility wrappers.
- [ ] Keep existing script names and arguments working for at least one migration release.
- [x] Add `tnt --version` and include the version in CLI status output.

### Completion Criteria

- [x] Tasker profiles do not need to change during migration.
- [x] All user-facing commands return meaningful exit codes.
- [x] Errors have concise terminal output, structured logs, and optional Android feedback.

## Phase 4: Modernize Configuration And State

- [x] Add validation for the existing shell configuration schema.
- [x] Add a versioned TOML configuration file.
- [x] Support importing the existing shell configuration.
- [x] Add `tnt config check` with actionable validation errors.
- [x] Add `tnt config migrate` with backup creation.
- [x] Add `tnt config migrate` with backup creation.
- [ ] Replace tab-separated state files with versioned JSON state.
- [x] Add versioned JSON state migration while retaining legacy files.
- [x] Add atomic state writes and explicit schema migration.
- [x] Add configurable command timeouts.
- [ ] Add bounded log rotation.
- [x] Quote notification action commands safely when paths contain spaces or shell characters.
- [x] Document which environment variables remain supported as one-off overrides.

### Completion Criteria

- [x] Invalid values are rejected before a scan changes notifications.
- [x] Upgrades do not silently overwrite user configuration.
- [x] State from the current release migrates without orphaning notifications or snoozes.

## Phase 5: Improve Daily Use

### Active Tasks

- [x] Add `always_show_active` so active tasks appear without a due date or outside today's window.
- [x] Add `TW_ALWAYS_SHOW_ACTIVE` support for active tasks outside the normal window.
- [x] Add an optional ongoing notification for active tasks.
- [x] Display current active duration where Android allows useful refresh behavior.
- [x] Keep active tasks ahead of normal reminders without disrupting their channel settings.

### Filtering And Policies

- [x] Add a configurable Taskwarrior filter for eligible reminders.
- [x] Add project and tag include/exclude rules.
- [x] Add an opt-out tag or UDA for individual tasks.
- [ ] Allow different reminder windows by project, tag, or urgency.
- [ ] Allow independent limits for active, execution-window, and overdue tasks.

### Dismissal And Snooze

- [ ] Add configurable dismissal modes: `next_scan`, `snooze`, `until_changed`, and `today`.
- [ ] Add configurable snooze presets.
- [ ] Allow the third notification button to be selected from Tomorrow, Snooze, or Open GUI.
- [ ] Show the snooze-until time in confirmation feedback.

### Health And Refresh

- [ ] Record the last successful scan, duration, task counts, and last error.
- [x] Make `tnt status` show the next eligible reminder and current channel state.
- [ ] Add a health notification after repeated scan failures without spamming every cycle.
- [ ] Add an optional recovery message when scans begin succeeding again.
- [x] Provide a stable post-sync refresh command.
- [x] Document how sync tools can invoke refresh after remote task changes arrive.

## Phase 6: Make The GUI A Control Center

- [x] Remove duplicated selection and formatting logic by consuming the shared core.
- [x] Present separate Active, Now, Soon, and Overdue sections.
- [x] Add project and tag filtering.
- [x] Add task details without turning each row into a wall of text.
- [x] Keep actions contextual to the selected task.
- [x] Add manual refresh with visible loading and failure states.
- [ ] Show health information from `tnt status`.
- [ ] Show channel setup status and provide a setup action.
- [x] Keep startup fast through a versioned shared cache.

### Completion Criteria

- [ ] Notifications and GUI always agree about task eligibility, order, status, and text.
- [ ] Opening cached data remains fast while manual refresh always requests live data.
- [ ] Every GUI action uses the same state-aware action service as notification buttons.

## Phase 7: Generalize Integrations

- [ ] Replace Jot-specific branching in action scripts with an integration adapter.
- [ ] Define lifecycle events such as `task_started`, `task_stopped`, and `task_completed`.
- [ ] Give integrations a stable environment, timeout, logging, and failure policy.
- [x] Keep Taskwarrior hooks disabled in Android notification actions.
- [x] Keep integration failures from undoing successful Taskwarrior actions.
- [ ] Document how external tools can consume lifecycle events safely.

## Phase 8: Release And Maintenance Quality

- [x] Add `.gitignore` entries for Python, editor, and test artifacts.
- [x] Add release notes and semantic version tags.
- [x] Test installation over an existing configuration.
- [x] Test clean installation in a fresh Termux environment.
- [x] Add a concise upgrade guide for configuration and state migrations.
- [x] Add issue templates for installation, notification, and Taskwarrior problems.
- [x] Keep the README focused on installation and daily use; move internals to dedicated documentation.

## Recommended Execution Order

1. Finish and commit Phase 0.
2. Build the Phase 1 test harness before restructuring behavior.
3. Complete the shared core and CLI in Phases 2 and 3.
4. Modernize configuration and state in Phase 4.
5. Implement `always_show_active`, filters, dismissal policies, and `tnt status` first from Phase 5.
6. Rebuild the GUI on the shared core.
7. Generalize integrations only after action behavior is centralized.

## Deferred Ideas

These may be useful later but should not delay the shared core or tests.

- [ ] Dynamic Tasker scheduling based on the next reminder boundary.
- [ ] Per-project notification channels.
- [ ] Notification body tap opening a specific task in the GUI.
- [ ] Importable Tasker project templates.
- [ ] A packaged Termux release instead of a copy-based installer.
