# State Lock Hardening Design

## Goal

Replace TNT's stale-directory lock with one kernel-managed advisory lock shared by its Bash and Python clients. A process exit releases the lock automatically, so TNT no longer decides whether a PID or timestamp makes a lock stale.

This design assumes users upgrade all installed TNT scripts before running scans or actions again. Old and new clients use different locking protocols and cannot coordinate during a mixed-version run.

## Current behavior

Notification scans and dismiss callbacks acquire a Bash `mkdir` lock at `.state.lock`. Python action controllers acquire a lock at the same path. The implementations do not recover stale locks the same way: Bash checks the recorded PID, while Python reclaims any lock older than 60 seconds. Both can race while removing a stale lock. Existing tests cover simple Python acquire and release only.

Pre-scan sync runs before the scan acquires the state lock. The scan then holds the lock while reading and updating notification state and posting notifications. Action controllers hold it while inspecting and mutating Taskwarrior state and updating notification state.

## Design

Use a persistent regular lock file at `<TW_STATE_DIR>/.state.lockfile`. The new name avoids colliding with the legacy `.state.lock` directory that an existing installation may leave behind. Never remove the new lock file after unlocking; all clients must lock the same inode.

Python clients use `fcntl.flock(fd, LOCK_EX | LOCK_NB)` in a monotonic-time retry loop. They release the lock and close the descriptor in a `finally` block. Keep the existing 10-second default timeout and raise `TimeoutError` when it expires.

Bash clients use the Termux `flock` executable with its command form and close-on-exec option to run the protected section. Each script starts a second, internal locked invocation after it has completed any pre-lock work. The outer scanner runs pre-scan sync once, then invokes itself through `flock`; the internal invocation skips sync and performs the scan. The dismiss callback uses the same pattern around its manifest update. This keeps the lock descriptor in the `flock` process instead of passing it to child commands. Use the same 10-second default timeout.

Both implementations use Linux's `flock(2)` advisory lock API. Require `flock` from the Termux `util-linux` package, check for it during installation and in diagnostics, and document the dependency. Keep the lock file empty and create it with owner-only permissions where possible.

If the lock cannot be opened or acquired, report an actionable error and leave notification state unchanged. Do not remove stale lock files or directories. The kernel releases the advisory lock when the owning process exits, including after an abnormal exit.

## Compatibility and upgrade

Users must pause Tasker scans and actions, upgrade all installed TNT scripts and Python modules, then resume Tasker. An old process may still hold `.state.lock` while a new process uses `.state.lockfile`; those processes do not coordinate. The installer must not delete the old lock directory or attempt to convert it while a process may be using it. The new code ignores that legacy path.

The existing state manifest and snooze files do not change. `TW_STATE_DIR`, the lock timeout default, Tasker command names, and pre-scan sync ordering remain unchanged.

## Components

- `scripts/taskwarrior_tnt/state.py`: create/open the lock file, acquire/release the Python advisory lock, and retain the context manager interface used by the action controller.
- `scripts/taskwarrior_tnt_common.sh`: provide `tnt_run_locked`, which invokes a command under the advisory lock with a bounded wait and close-on-exec behavior.
- `scripts/taskwarrior_notify_due_tasks.sh`: preserve the current pre-scan sync boundary and hold the lock across notification state reads and writes.
- `scripts/taskwarrior_forget_notification.sh`: protect manifest removal with the same lock file.
- `install.sh`, `README.md`, and the installer/diagnostic tests: require and explain `flock`.
- `tests/test_tnt.py`: cover lock behavior and cross-language coordination.

## Verification

Tests will prove that Python and Bash clients cannot enter the protected section together, that a second client times out without changing state, that a waiting client acquires after the holder exits, and that process termination releases the lock. Tests will also cover paths with spaces, lock-file permissions where supported, missing `flock`, and continued operation when a legacy `.state.lock` directory exists.

The existing tests will verify that pre-scan sync still completes before the scan lock is acquired and that action and dismissal state updates remain serialized. CI will continue running shell syntax checks, ShellCheck, Python compilation, and the complete test suite.

## Out of scope

This change does not migrate manifest or snooze contents to JSON, redesign installer staging, alter Tasker profiles, or change notification behavior. It does not promise coordination between old and new TNT processes during an upgrade.
