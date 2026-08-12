"""State-aware Taskwarrior action planning for TNT clients."""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum


class ActionStatus(str, Enum):
    READY = "ready"
    ALREADY_SATISFIED = "already_satisfied"
    STALE = "stale"


@dataclass(frozen=True)
class ActionPlan:
    action: str
    uuid: str
    task_args: tuple[str, ...] = ()
    status: ActionStatus = ActionStatus.READY


def plan_task_action(action: str, uuid: str, status: str, started: bool = False) -> ActionPlan:
    """Plan a hookless Taskwarrior action from a current task snapshot."""
    if status != "pending":
        return ActionPlan(action, uuid, status=ActionStatus.STALE)
    if action == "start" and started:
        return ActionPlan(action, uuid, status=ActionStatus.ALREADY_SATISFIED)
    if action == "stop" and not started:
        return ActionPlan(action, uuid, status=ActionStatus.ALREADY_SATISFIED)
    if action in {"start", "stop", "done"}:
        return ActionPlan(
            action,
            uuid,
            ("rc.hooks:off", "rc.confirmation:no", uuid, action),
        )
    raise ValueError(f"unsupported Taskwarrior action: {action}")


def plan_due_modifier(uuid: str, modifier: str, status: str) -> ActionPlan:
    """Plan a hookless due-date modification for a pending task."""
    if status != "pending":
        return ActionPlan("modify", uuid, status=ActionStatus.STALE)
    return ActionPlan(
        "modify",
        uuid,
        ("rc.hooks:off", "rc.confirmation:no", uuid, "modify", modifier),
    )
