"""Optional external integrations used by TNT actions."""

from __future__ import annotations

import os
import shutil
import subprocess
from dataclasses import dataclass
from enum import Enum


class IntegrationStatus(str, Enum):
    DISABLED = "disabled"
    MISSING = "missing"
    OK = "ok"
    FAILED = "failed"


@dataclass(frozen=True)
class IntegrationResult:
    status: IntegrationStatus
    output: str = ""


@dataclass(frozen=True)
class JotIntegration:
    binary: str = "jot"
    enabled: bool = True

    def run(self, action: str, uuid: str) -> IntegrationResult:
        if not self.enabled:
            return IntegrationResult(IntegrationStatus.DISABLED)
        if not _is_available(self.binary):
            return IntegrationResult(IntegrationStatus.MISSING)
        command = [self.binary, "timelog", action, uuid]
        result = subprocess.run(command, capture_output=True, text=True, check=False)
        output = (result.stdout or result.stderr or "").strip()
        if result.returncode == 0:
            return IntegrationResult(IntegrationStatus.OK, output)
        return IntegrationResult(IntegrationStatus.FAILED, output)


def _is_available(binary: str) -> bool:
    if os.path.isfile(binary) and os.access(binary, os.X_OK):
        return True
    return shutil.which(binary) is not None
