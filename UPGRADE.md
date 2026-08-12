# Upgrade Guide

## Existing installations

Run `install.sh` from the new checkout. The installer preserves
`~/.termux/tasker/taskwarrior_tasker.conf` and writes the latest example beside
it as `taskwarrior_tasker.conf.example`.

Run the installed doctor command after upgrading:

```sh
~/.termux/tasker/taskwarrior_notify_due_tasks.sh --doctor
```

## Configuration migration

The shell configuration remains supported. To create a versioned TOML copy,
run:

```sh
~/.termux/tasker/tnt config migrate
```

An existing TOML destination is backed up with a `.bak` suffix. Existing
`TW_*` environment overrides continue to take precedence for one-off runs.

## State migration

To create a versioned JSON snapshot while retaining the legacy state files:

```sh
TW_STATE_DIR="$HOME/.local/state/taskwarrior-tnt" ~/.termux/tasker/tnt state migrate
```

The migration is non-destructive.
