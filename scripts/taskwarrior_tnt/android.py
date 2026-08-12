"""Termux:API command adapter for TNT Android interactions."""

from __future__ import annotations

import subprocess
from dataclasses import dataclass
from typing import Mapping, Sequence


class AndroidCommandError(RuntimeError):
    """Raised when a Termux:API command fails."""


@dataclass(frozen=True)
class Android:
    notification_bin: str = "termux-notification"
    notification_remove_bin: str = "termux-notification-remove"
    channel_bin: str = "termux-notification-channel"
    toast_bin: str = "termux-toast"
    env: Mapping[str, str] | None = None

    def _run(self, command: Sequence[str]) -> str:
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            check=False,
            env=dict(self.env) if self.env is not None else None,
        )
        output = (result.stdout or result.stderr or "").strip()
        if result.returncode != 0:
            raise AndroidCommandError(output or f"command failed: {command[0]}")
        return output

    def notify(self, *args: str) -> str:
        return self._run([self.notification_bin, *args])

    def remove_notification(self, notification_id: str) -> str:
        return self._run([self.notification_remove_bin, notification_id])

    def create_channel(self, channel_id: str, name: str) -> str:
        return self._run([self.channel_bin, channel_id, name])

    def toast(self, message: str) -> str:
        return self._run([self.toast_bin, message])
