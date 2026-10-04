"""Typed access to TNT notification and snooze state files."""

from __future__ import annotations

import fcntl
import json
import os
import shutil
import tempfile
import time
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class ManifestEntry:
    notification_id: str
    uuid: str
    fingerprint: str = ""


def read_manifest(path: str | Path) -> list[ManifestEntry]:
    entries: list[ManifestEntry] = []
    try:
        lines = Path(path).read_text().splitlines()
    except OSError:
        return entries
    for line in lines:
        fields = line.split("\t")
        if len(fields) >= 2 and fields[0] and fields[1]:
            entries.append(ManifestEntry(fields[0], fields[1], fields[2] if len(fields) > 2 else ""))
    return entries


def write_manifest(path: str | Path, entries: list[ManifestEntry]) -> None:
    _atomic_write(
        Path(path),
        "".join(
            f"{entry.notification_id}\t{entry.uuid}\t{entry.fingerprint}\n"
            for entry in entries
        ),
    )


def remove_manifest_id(path: str | Path, notification_id: str) -> None:
    entries = [
        entry for entry in read_manifest(path) if entry.notification_id != notification_id
    ]
    write_manifest(path, entries)


def read_snoozes(path: str | Path, now_epoch: int) -> dict[str, int]:
    snoozes: dict[str, int] = {}
    try:
        lines = Path(path).read_text().splitlines()
    except OSError:
        return snoozes
    for line in lines:
        uuid, separator, until = line.partition("\t")
        if not separator or not uuid:
            continue
        try:
            until_epoch = int(until)
        except ValueError:
            continue
        if until_epoch > now_epoch:
            snoozes[uuid] = until_epoch
    return snoozes


def write_snoozes(path: str | Path, snoozes: dict[str, int]) -> None:
    _atomic_write(
        Path(path),
        "".join(f"{uuid}\t{until}\n" for uuid, until in sorted(snoozes.items())),
    )


def upsert_snooze(path: str | Path, uuid: str, until_epoch: int) -> None:
    snoozes = read_snoozes(path, 0)
    snoozes[uuid] = until_epoch
    write_snoozes(path, snoozes)


def remove_snooze(path: str | Path, uuid: str) -> None:
    snoozes = read_snoozes(path, 0)
    snoozes.pop(uuid, None)
    write_snoozes(path, snoozes)


def migrate_to_json(state_dir: str | Path, output: str | Path | None = None) -> Path:
    """Write a versioned JSON snapshot while retaining legacy state files."""
    directory = Path(state_dir)
    destination = Path(output) if output else directory / "state.json"
    manifest = read_manifest(directory / "active-notifications")
    snoozes = read_snoozes(directory / "snoozed-tasks", 0)
    payload = {
        "schema_version": 1,
        "active_notifications": [
            {
                "notification_id": item.notification_id,
                "uuid": item.uuid,
                "fingerprint": item.fingerprint,
            }
            for item in manifest
        ],
        "snoozed_tasks": snoozes,
    }
    if destination.exists():
        shutil.copy2(destination, destination.with_suffix(destination.suffix + ".bak"))
    _atomic_write(destination, json.dumps(payload, indent=2, sort_keys=True) + "\n")
    return destination


@contextmanager
def state_lock(state_dir: str | Path, timeout: float = 10.0):
    """Acquire the advisory state lock shared by TNT clients."""
    directory = Path(state_dir)
    directory.mkdir(parents=True, exist_ok=True)
    lock_file = directory / ".state.lockfile"
    descriptor = os.open(lock_file, os.O_CREAT | os.O_RDWR, 0o600)
    try:
        os.fchmod(descriptor, 0o600)
        deadline = time.monotonic() + timeout
        while True:
            try:
                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise TimeoutError("timed out waiting for Taskwarrior TNT state lock")
                time.sleep(min(0.1, remaining))
        try:
            yield
        finally:
            fcntl.flock(descriptor, fcntl.LOCK_UN)
    finally:
        os.close(descriptor)


def _atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(content)
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise
