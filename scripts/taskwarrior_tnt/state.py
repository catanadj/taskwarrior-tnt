"""Typed access to TNT notification and snooze state files."""

from __future__ import annotations

import os
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


@contextmanager
def state_lock(state_dir: str | Path, timeout: float = 10.0, stale_after: float = 60.0):
    """Acquire the same mkdir-based lock convention used by shell clients."""
    directory = Path(state_dir)
    lock_dir = directory / ".state.lock"
    directory.mkdir(parents=True, exist_ok=True)
    deadline = time.monotonic() + timeout
    while True:
        try:
            lock_dir.mkdir()
            (lock_dir / "pid").write_text(str(os.getpid()))
            (lock_dir / "epoch").write_text(str(int(time.time())))
            break
        except FileExistsError:
            try:
                epoch = int((lock_dir / "epoch").read_text())
            except (OSError, ValueError):
                epoch = int(time.time())
            if time.time() - epoch > stale_after:
                for child in lock_dir.iterdir():
                    child.unlink(missing_ok=True)
                lock_dir.rmdir()
                continue
            if time.monotonic() >= deadline:
                raise TimeoutError("timed out waiting for Taskwarrior TNT state lock")
            time.sleep(0.1)
    try:
        yield
    finally:
        for child in lock_dir.iterdir():
            child.unlink(missing_ok=True)
        lock_dir.rmdir()


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
