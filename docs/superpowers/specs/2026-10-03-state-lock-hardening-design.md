# State Lock Hardening Design

## Goal

Replace TNT's stale-directory lock with one kernel-managed advisory lock shared by its Bash and Python clients. A process exit releases the lock automatically, so TNT no longer decides whether a PID or timestamp makes a lock stale.

This design assumes users upgrade all installed TNT scripts before running scans or actions again. Old and new clients use different locking protocols and cannot coordinate during a mixed-version run.

## Current behavior

Notification scans, dismiss callbacks, and the Complete, Start/Stop, and Snooze actions acquire a Bash `mkdir` lock at `.state.lock`. Python action controllers acquire a lock at the same path. The implementations do not recover stale locks the same way: Bash checks the recorded PID, while Python reclaims any lock older than 60 seconds. Both can race while removing a stale lock. Existing tests cover simple Python acquire and release only.

Pre-scan sync runs before the scan acquires the state lock. The scan then holds the lock while reading and updating notification state and posting notifications. Action controllers hold it while inspecting and mutating Taskwarrior state and updating notification state.

## Design

Use a persistent regular lock file at `<TW_STATE_DIR>/.state.lockfile`. The new name avoids colliding with the legacy `.state.lock` directory that an existing installation may leave behind. Never remove the new lock file after unlocking; all clients must lock the same inode.

Python clients use `fcntl.flock(fd, LOCK_EX | LOCK_NB)` in a monotonic-time retry loop. They release the lock and close the descriptor in a `finally` block. Keep the existing 10-second default timeout and raise `TimeoutError` when it expires.

Bash clients retain the existing `tnt_acquire_state_lock` and `tnt_release_state_lock` calls, backed by the same lock file. Acquisition opens a Bash file descriptor and uses util-linux `flock` in descriptor mode with a bounded wait. Release unlocks and closes the descriptor. Preserve the existing `TW_STATE_LOCK_HELD` reentrant behavior and critical-section boundaries, including early release before follow-up refreshes. Keep the 10-second default timeout. Child processes may inherit the descriptor; current TNT callers run those commands synchronously and explicitly unlock before leaving the protected section.

Both implementations use Linux's `flock(2)` advisory lock API. Require `flock` from the Termux `util-linux` package, check for it during installation and in diagnostics, and document the dependency. Keep the lock file empty and create it with owner-only permissions where possible.

If the lock cannot be opened or acquired, report an actionable error and leave notification state unchanged. Do not remove stale lock files or directories. The kernel releases the advisory lock when the owning process exits, including after an abnormal exit.

## Compatibility and upgrade

Users must pause Tasker scans and actions, upgrade all installed TNT scripts and Python modules, then resume Tasker. An old process may still hold `.state.lock` while a new process uses `.state.lockfile`; those processes do not coordinate. The installer must not delete the old lock directory or attempt to convert it while a process may be using it. The new code ignores that legacy path.

The existing state manifest and snooze files do not change. `TW_STATE_DIR`, the lock timeout default, Tasker command names, and pre-scan sync ordering remain unchanged.

## Components

- `scripts/taskwarrior_tnt/state.py`: create/open the lock file, acquire/release the Python advisory lock, and retain the context manager interface used by the action controller.
- `scripts/taskwarrior_tnt_common.sh`: implement the existing acquire/release API with a persistent file descriptor and util-linux `flock`.
- `scripts/taskwarrior_notify_due_tasks.sh`, `scripts/taskwarrior_forget_notification.sh`, `scripts/taskwarrior_complete_task.sh`, `scripts/taskwarrior_start_stop_task.sh`, and `scripts/taskwarrior_snooze_task.sh`: retain their existing lock boundaries and share the advisory lock through the common helper.
- `install.sh`, `README.md`, and the installer/diagnostic tests: require and explain `flock`.
- `tests/test_tnt.py`: cover lock behavior and cross-language coordination.

## Verification

Tests will prove that Python and Bash clients cannot enter the protected section together, that a second client times out without changing state, that a waiting client acquires after the holder exits, and that process termination releases the lock. Tests will also cover paths with spaces, lock-file permissions where supported, missing `flock`, and continued operation when a legacy `.state.lock` directory exists.

The existing tests will verify that pre-scan sync still completes before the scan lock is acquired and that action and dismissal state updates remain serialized. CI will continue running shell syntax checks, ShellCheck, Python compilation, and the complete test suite.

## Out of scope

This change does not migrate manifest or snooze contents to JSON, redesign installer staging, alter Tasker profiles, or change notification behavior. It does not promise coordination between old and new TNT processes during an upgrade.
