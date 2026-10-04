# State Lock Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace stale directory locks with a kernel-managed advisory lock shared by TNT's Bash and Python clients.

**Architecture:** Python clients will use `fcntl.flock` on one persistent lock file. Bash clients will keep the existing acquire/release API and use util-linux `flock` on a shared file descriptor, preserving each script's current lock boundaries. Pre-scan sync remains outside the scan lock, and the installer and documentation will require `flock`.

**Tech Stack:** Python 3, Bash, Termux util-linux `flock`, unittest, ShellCheck.

**Spec:** `docs/superpowers/specs/2026-10-03-state-lock-hardening-design.md`

## Global Constraints

- Use `<TW_STATE_DIR>/.state.lockfile` as the persistent regular lock file.
- Python and Bash clients must use Linux `flock(2)` advisory locking.
- Keep the lock timeout default at 10 seconds.
- Keep pre-scan sync before the scan lock.
- Do not remove or convert the legacy `.state.lock` directory.
- Pause Tasker scans and actions while upgrading installed TNT files.
- Keep manifest and snooze file formats unchanged.

## Review Focus

- A Python or Bash lock holder exits or is killed; the kernel releases its lock and a waiter proceeds. Test in Tasks 1 and 2.
- Python and Bash contend for the same file and never enter together. Test in Task 2.
- A legacy `.state.lock` directory exists beside the new lock file. Test in Task 1.
- The state directory path contains spaces. Test in Task 2.
- `flock` is missing or is Android Toybox's limited implementation, or lock acquisition times out. Test clear errors and unchanged state in Tasks 2 and 3.

---

### Task 1: Implement Python Advisory Locking

**Files:**
- Modify: `scripts/taskwarrior_tnt/state.py`
- Test: `tests/test_tnt.py`

**Interfaces:**
- Consumes: Existing callers use `state_lock(state_dir, timeout=10.0)` as a context manager.
- Produces: Preserve `state_lock(state_dir: str | Path, timeout: float = 10.0)`; it locks `<state_dir>/.state.lockfile` with `fcntl.flock`.

- [x] **Step 1: Add Python lock format tests**
  Assert entering the context creates a regular, owner-only `.state.lockfile`, leaves an existing `.state.lock` directory untouched, and leaves the new lock file in place after release. Update existing lock lifecycle and state-migration assertions to expect the persistent lock file.
- [x] **Step 2: Run the focused tests and confirm they fail**
  Run: `PYTHONPATH=scripts:. python3 -m unittest tests.test_tnt.TntHarness.test_state_lock_uses_persistent_file_and_preserves_legacy_directory -v`
  Expected: The existing implementation creates a lock directory and fails the new regular-file assertions.
- [x] **Step 3: Add Python contention and process-exit tests**
  Add `test_state_lock_times_out_while_held` and `test_state_lock_releases_after_holder_exit`. Assert a second process times out while a holder is active, then acquires after normal exit and after termination.
- [x] **Step 4: Run the new contention tests and confirm they fail**
  Run: `PYTHONPATH=scripts:. python3 -m unittest tests.test_tnt.TntHarness.test_state_lock_times_out_while_held tests.test_tnt.TntHarness.test_state_lock_releases_after_holder_exit -v`
  Expected: FAIL because Python's current directory-lock implementation does not implement the new file-lock contract.
- [x] **Step 5: Implement the Python lock context manager**
  Open the persistent lock file without truncating it, set owner-only permissions when creating it, acquire `fcntl.flock(fd, LOCK_EX | LOCK_NB)` with a monotonic deadline, and always unlock and close the descriptor.
- [x] **Step 6: Run focused lock tests**
  Run: `PYTHONPATH=scripts:. python3 -m unittest tests.test_tnt.TntHarness.test_state_lock_uses_persistent_file_and_preserves_legacy_directory tests.test_tnt.TntHarness.test_state_lock_times_out_while_held tests.test_tnt.TntHarness.test_state_lock_releases_after_holder_exit -v`
  Expected: PASS, including contention and automatic release cases.

### Task 2: Coordinate All Bash State Clients

**Files:**
- Modify: `scripts/taskwarrior_tnt_common.sh`
- Test: `tests/test_tnt.py`

**Interfaces:**
- Consumes: Python's persistent lock path and `flock(2)` semantics from Task 1.
- Produces: Preserve `tnt_acquire_state_lock(state_dir, timeout_seconds=10)` and `tnt_release_state_lock()`. Acquisition locks `<state_dir>/.state.lockfile` in the current Bash process; release unlocks and closes its descriptor.

- [x] **Step 1: Add shell/Python lock integration tests**
  Add `test_shell_and_python_share_state_lock`, `test_shell_state_lock_supports_paths_with_spaces`, and `test_scan_sync_runs_before_state_lock`. Assert the shell waits while Python holds the lock, Python waits while Bash holds it, timeout leaves a manifest unchanged, a path with spaces works, a killed Bash owner releases the lock, and sync logs before Bash acquires the lock.
- [x] **Step 2: Run the focused contention test and confirm it fails**
  Run: `PYTHONPATH=scripts:. python3 -m unittest tests.test_tnt.TntHarness.test_shell_and_python_share_state_lock tests.test_tnt.TntHarness.test_shell_state_lock_supports_paths_with_spaces tests.test_tnt.TntHarness.test_scan_sync_runs_before_state_lock -v`
  Expected: FAIL because the shell helper still locks the old directory and cannot coordinate with Python's new file lock.
- [x] **Step 3: Implement the Bash acquire/release functions**
  Create the state directory and owner-only lock file, open it without truncating, and acquire it with `flock -E 75 -w <timeout> <fd>`. Preserve the reentrant `TW_STATE_LOCK_HELD` behavior. On release, call `flock -u <fd>` and close the descriptor. Report timeout and dependency errors clearly.
- [x] **Step 4: Verify all existing shell lock call sites use the shared API**
  Confirm the notifier, dismissal, Complete, Start/Stop, and Snooze scripts still acquire before state or task mutation and release at their existing boundaries. Preserve pre-scan sync before scan lock acquisition and early unlock before targeted refresh.
- [x] **Step 5: Run focused shell-lock tests**
  Run: `PYTHONPATH=scripts:. python3 -m unittest tests.test_tnt.TntHarness.test_shell_and_python_share_state_lock tests.test_tnt.TntHarness.test_shell_state_lock_supports_paths_with_spaces tests.test_tnt.TntHarness.test_scan_sync_runs_before_state_lock -v`
  Expected: PASS for mutual exclusion, timeout, path-with-spaces, and sync-order assertions.

### Task 3: Require the Lock Tool and Document Upgrade Behavior

**Files:**
- Modify: `install.sh`
- Modify: `scripts/taskwarrior_notify_due_tasks.sh` (doctor output)
- Modify: `README.md`
- Test: `tests/test_tnt.py`

**Interfaces:**
- Consumes: The runtime dependency on `flock` from Task 2.
- Produces: Installer and doctor diagnostics that identify a missing `flock` binary and tell the user to install `util-linux`.

- [x] **Step 1: Add installer and doctor tests for missing or incompatible `flock`**
  Add `test_flock_dependency_diagnostics`. Run installer and doctor with a controlled `PATH` lacking `flock` and with a fake Toybox `flock`; assert both cases report the `util-linux` remedy.
- [x] **Step 2: Run the focused dependency tests and confirm they fail**
  Run: `PYTHONPATH=scripts:. python3 -m unittest tests.test_tnt.TntHarness.test_flock_dependency_diagnostics -v`
  Expected: FAIL because current installer and doctor do not check `flock`.
- [x] **Step 3: Add the dependency checks**
  Installer and doctor require util-linux `flock` and report the command `pkg install util-linux` when missing or when only Toybox's implementation is found. A scan or action that needs locking exits with a clear error if util-linux `flock` is unavailable.
- [x] **Step 4: Update installation and upgrade documentation**
  Add `util-linux` to Termux package setup. Explain that users should pause Tasker scans/actions during upgrades and resume them after all TNT files are replaced.
- [x] **Step 5: Run focused dependency tests**
  Run: `PYTHONPATH=scripts:. python3 -m unittest tests.test_tnt.TntHarness.test_flock_dependency_diagnostics -v`
  Expected: PASS.

### Task 4: Full Verification and Review

**Files:**
- Verify: `scripts/taskwarrior_tnt/state.py`
- Verify: `scripts/taskwarrior_tnt_common.sh`
- Verify: `scripts/taskwarrior_notify_due_tasks.sh`
- Verify: `scripts/taskwarrior_forget_notification.sh`
- Verify: `scripts/taskwarrior_complete_task.sh`, `scripts/taskwarrior_start_stop_task.sh`, and `scripts/taskwarrior_snooze_task.sh`
- Verify: `install.sh`, `README.md`, and `tests/test_tnt.py`

- [x] **Step 1: Run the complete unit suite**
  Run: `PYTHONPATH=scripts:. python3 -m unittest discover -s tests -v`
  Expected: PASS.
- [x] **Step 2: Run shell syntax and lint checks**
  Run: `bash -n install.sh scripts/*.sh && shellcheck install.sh scripts/*.sh`
  Expected: No syntax errors or ShellCheck findings.
- [x] **Step 3: Check the final diff**
  Run: `git diff --check`
  Expected: No whitespace errors; confirm unrelated pre-existing modifications remain unstaged and unchanged.
