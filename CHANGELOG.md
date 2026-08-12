# Changelog

## 0.2.0

- Added shared Python reminder, state, action, and Android command boundaries.
- Added `tnt scan`, `doctor`, `status`, configuration migration, and state migration commands.
- Added active-task visibility, configurable Taskwarrior filters, project/tag eligibility rules, and command timeouts.
- Added notification channel fallback, stale-action handling, snooze support, and regression coverage.

Configuration overrides remain supported through the existing `TW_*` shell variables. The installed shell configuration is still the compatibility source of truth; `tnt config migrate` writes a TOML representation with a backup of any existing destination.
