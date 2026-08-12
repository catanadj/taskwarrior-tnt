#!/usr/bin/env python3
"""Dependency-free integration tests for Taskwarrior TNT."""

from __future__ import annotations

import importlib.util
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import types
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

from taskwarrior_tnt.formatting import (
    clean_text,
    format_delta,
    parse_iso_duration,
    parse_task_date,
)
from taskwarrior_tnt.policy import reminder_bucket, select_priority
from taskwarrior_tnt.models import Reminder, TaskRecord
from taskwarrior_tnt.taskwarrior import (
    TaskwarriorCommandError,
    export_pending,
    normalize_task,
    normalize_tasks,
)
from taskwarrior_tnt.state import (
    ManifestEntry,
    read_manifest,
    read_snoozes,
    remove_manifest_id,
    remove_snooze,
    upsert_snooze,
    write_manifest,
)
from taskwarrior_tnt.android import Android, AndroidCommandError
from taskwarrior_tnt.actions import ActionStatus, plan_due_modifier, plan_task_action
from taskwarrior_tnt.integrations import IntegrationStatus, JotIntegration
from taskwarrior_tnt.reminders import build_reminders


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
FIXED_NOW = datetime(2026, 8, 12, 13, 0, tzinfo=timezone(timedelta(hours=3)))
FIXED_NOW_VALUE = "2026-08-12T13:00:00+03:00"


class TntHarness(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = Path(tempfile.mkdtemp(prefix="taskwarrior-tnt-test-"))
        self.bin_dir = self.temp_dir / "bin"
        self.state_dir = self.temp_dir / "state"
        self.bin_dir.mkdir()
        self.calls_file = self.temp_dir / "calls.log"
        self.export_calls_file = self.temp_dir / "export-calls.log"
        self.task_data: list[dict[str, object]] = []
        self.task_status = "pending"
        self.task_started = False
        self._write_task_command()
        for name in (
            "termux-notification",
            "termux-notification-remove",
            "termux-notification-channel",
            "termux-toast",
        ):
            self._write_recording_command(name)

    def tearDown(self) -> None:
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def _write_executable(self, path: Path, content: str) -> None:
        path.write_text(content)
        path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def _write_task_command(self) -> None:
        path = self.bin_dir / "task"
        self._write_executable(
            path,
            """#!/usr/bin/env python3
import importlib.util
import json
import os
import sys

if "export" in sys.argv:
    with open(os.environ["TNT_TEST_EXPORT_CALLS"], "a", encoding="utf-8") as handle:
        handle.write("task " + " ".join(sys.argv[1:]) + "\\n")
    uuid = os.environ.get("TNT_TEST_UUID", "11111111-1111-1111-1111-111111111111")
    status = os.environ.get("TNT_TEST_STATUS", "pending")
    started = os.environ.get("TNT_TEST_STARTED", "0") == "1"
    data = json.loads(os.environ.get("TNT_TEST_TASKS", "[]"))
    if status != "pending":
        data = [{"uuid": uuid, "status": status}]
    elif started:
        data = [{**item, "start": "20260101T120000"} for item in data]
    print(json.dumps(data))
    raise SystemExit(0)

with open(os.environ["TNT_TEST_CALLS"], "a", encoding="utf-8") as handle:
    handle.write("task " + " ".join(sys.argv[1:]) + "\\n")
if os.environ.get("TNT_TEST_ACTION_FAIL") == "1":
    print("simulated Taskwarrior action failure", file=sys.stderr)
    raise SystemExit(7)
""",
        )

    def _write_recording_command(self, name: str) -> None:
        failure = ""
        if name == "termux-notification-channel":
            failure = (
                'if [[ "${TNT_TEST_CHANNEL_FAIL:-0}" == "1" ]]; then\n'
                '  echo "simulated channel failure" >&2\n'
                '  exit 9\n'
                'fi\n'
            )
        self._write_executable(
            self.bin_dir / name,
            f"""#!/usr/bin/env bash
{failure}
printf '%s %s\\n' "${{0##*/}}" "$*" >> "${{TNT_TEST_CALLS}}"
""",
        )

    def _env(self, **overrides: str) -> dict[str, str]:
        task_json = json.dumps(self.task_data, separators=(",", ":"))
        env = os.environ.copy()
        env.update(
            {
                "PATH": f"{self.bin_dir}:{env.get('PATH', '')}",
                "TNT_TEST_CALLS": str(self.calls_file),
                "TNT_TEST_EXPORT_CALLS": str(self.export_calls_file),
                "TNT_TEST_TASKS": task_json,
                "TNT_TEST_STATUS": self.task_status,
                "TNT_TEST_STARTED": "1" if self.task_started else "0",
                "TNT_TEST_UUID": str(
                    (self.task_data[0] if self.task_data else {}).get(
                        "uuid", "11111111-1111-1111-1111-111111111111"
                    )
                ),
                "TW_CONFIG_FILE": str(self.temp_dir / "missing.conf"),
                "TW_STATE_DIR": str(self.state_dir),
                "TW_GUI_CACHE_FILE": str(self.state_dir / "gui-cache.json"),
                "TW_ACTION_LOG_FILE": str(self.state_dir / "action.log"),
                "TW_COMPLETE_SCRIPT": str(SCRIPTS / "taskwarrior_complete_task.sh"),
                "TW_FORGET_SCRIPT": str(SCRIPTS / "taskwarrior_forget_notification.sh"),
                "TW_SNOOZE_SCRIPT": str(SCRIPTS / "taskwarrior_snooze_task.sh"),
                "TW_START_STOP_SCRIPT": str(SCRIPTS / "taskwarrior_start_stop_task.sh"),
                "TW_NOTIFY_SCRIPT": str(SCRIPTS / "taskwarrior_notify_due_tasks.sh"),
                "TW_JOT_TIMELOG_ENABLED": "0",
                "TW_TEST_NOW": FIXED_NOW_VALUE,
                "TW_WINDOW_PAST_HOURS": "2",
                "TW_WINDOW_FUTURE_HOURS": "2",
                "TW_MAX_TASKS": "12",
            }
        )
        env.update(overrides)
        return env

    def run_script(
        self, script: str, *args: str, check: bool = True, **env_overrides: str
    ) -> subprocess.CompletedProcess[str]:
        result = subprocess.run(
            ["bash", str(SCRIPTS / script), *args],
            cwd=ROOT,
            env=self._env(**env_overrides),
            capture_output=True,
            text=True,
            check=False,
        )
        if check and result.returncode != 0:
            self.fail(
                f"{script} failed with {result.returncode}:\n"
                f"stdout: {result.stdout}\nstderr: {result.stderr}"
            )
        return result

    def calls(self) -> list[str]:
        if not self.calls_file.exists():
            return []
        return self.calls_file.read_text().splitlines()

    def task(self, uuid: str, description: str, due: datetime, **extra: object) -> None:
        self.task_data.append(
            {
                "uuid": uuid,
                "description": description,
                "due": due.strftime("%Y%m%dT%H%M%S"),
                "status": "pending",
                **extra,
            }
        )

    def test_channels_are_created_once_and_notifications_are_routed(self) -> None:
        now = FIXED_NOW
        self.task("a" * 36, "overdue", now - timedelta(hours=3))
        self.task("b" * 36, "window", now + timedelta(minutes=30))

        first = self.run_script("taskwarrior_notify_due_tasks.sh")
        second = self.run_script("taskwarrior_notify_due_tasks.sh")

        self.assertIn("Tracked 2", first.stdout)
        self.assertIn("Unchanged:", second.stdout)
        calls = self.calls()
        self.assertEqual(3, sum(line.startswith("termux-notification-channel ") for line in calls))
        notifications = [line for line in calls if line.startswith("termux-notification ")]
        self.assertEqual(2, len(notifications))
        self.assertTrue(any("--channel taskwarrior-tnt-window" in line for line in notifications))
        self.assertTrue(any("--channel taskwarrior-tnt-overdue" in line for line in notifications))

    def test_active_and_window_tasks_beat_overdue_backlog(self) -> None:
        now = FIXED_NOW
        self.task("a" * 36, "old overdue", now - timedelta(hours=3))
        self.task("b" * 36, "active", now - timedelta(minutes=30))
        self.task("c" * 36, "window", now + timedelta(minutes=30))

        result = self.run_script("taskwarrior_notify_due_tasks.sh", TW_MAX_TASKS="2")
        self.assertIn("Tracked 2", result.stdout)
        notifications = "\n".join(self.calls())
        self.assertIn("active", notifications)
        self.assertIn("window", notifications)
        self.assertNotIn("old overdue", notifications)

    def test_window_boundaries_use_injected_clock(self) -> None:
        fixed_now = "2026-08-12T13:00:00+00:00"
        self.task("a" * 36, "boundary start", datetime(2026, 8, 12, 11, 0))
        self.task("b" * 36, "inside window", datetime(2026, 8, 12, 15, 0))
        self.task("c" * 36, "earlier today", datetime(2026, 8, 12, 10, 59))
        self.task("d" * 36, "yesterday", datetime(2026, 8, 11, 10, 0))
        self.task("e" * 36, "tomorrow task", datetime(2026, 8, 13, 10, 0))

        result = self.run_script(
            "taskwarrior_notify_due_tasks.sh",
            TW_TEST_NOW=fixed_now,
            TW_WINDOW_PAST_HOURS="2",
            TW_WINDOW_FUTURE_HOURS="2",
        )

        self.assertIn("Tracked 3", result.stdout)
        notifications = "\n".join(self.calls())
        self.assertIn("boundary start", notifications)
        self.assertIn("inside window", notifications)
        self.assertIn("earlier today", notifications)
        self.assertNotIn("yesterday", notifications)
        self.assertNotIn("tomorrow task", notifications)

    def test_quiet_hours_skip_notifications(self) -> None:
        self.task(
            "c" * 36,
            "quiet task",
            datetime(2026, 8, 12, 13, 30),
        )

        result = self.run_script(
            "taskwarrior_notify_due_tasks.sh",
            TW_TEST_NOW="2026-08-12T13:00:00+00:00",
            TW_QUIET_HOURS_ENABLED="1",
            TW_QUIET_HOURS_START="12:00",
            TW_QUIET_HOURS_END="14:00",
        )

        self.assertIn("Quiet hours active", result.stdout)
        self.assertFalse(any(line.startswith("termux-notification ") for line in self.calls()))

    def test_quiet_hours_crossing_midnight(self) -> None:
        self.task(
            "7" * 36,
            "early task",
            datetime(2026, 8, 12, 6, 30),
        )

        during = self.run_script(
            "taskwarrior_notify_due_tasks.sh",
            TW_TEST_NOW="2026-08-12T06:00:00+00:00",
            TW_QUIET_HOURS_ENABLED="1",
            TW_QUIET_HOURS_START="22:00",
            TW_QUIET_HOURS_END="07:00",
        )
        self.assertIn("Quiet hours active", during.stdout)
        self.assertFalse(any(line.startswith("termux-notification ") for line in self.calls()))

        after = self.run_script(
            "taskwarrior_notify_due_tasks.sh",
            TW_TEST_NOW="2026-08-12T07:00:00+00:00",
            TW_QUIET_HOURS_ENABLED="1",
            TW_QUIET_HOURS_START="22:00",
            TW_QUIET_HOURS_END="07:00",
            TW_WINDOW_FUTURE_HOURS="2",
        )
        self.assertIn("Tracked 1", after.stdout)

    def test_local_snooze_expires_and_task_reappears(self) -> None:
        uuid = "99999999-0000-0000-0000-000000000000"
        self.task(uuid, "snoozed task", datetime(2026, 8, 12, 13, 30))
        fixed_now = "2026-08-12T13:00:00+00:00"

        self.run_script(
            "taskwarrior_snooze_task.sh",
            uuid,
            "765432",
            "1h",
            TW_TEST_NOW=fixed_now,
        )
        snooze_file = self.state_dir / "snoozed-tasks"
        self.assertTrue(snooze_file.exists())
        self.assertIn(uuid, snooze_file.read_text())

        before = self.run_script(
            "taskwarrior_notify_due_tasks.sh",
            TW_TEST_NOW="2026-08-12T13:30:00+00:00",
        )
        self.assertIn("Tracked 0", before.stdout)

        after = self.run_script(
            "taskwarrior_notify_due_tasks.sh",
            TW_TEST_NOW="2026-08-12T14:01:00+00:00",
        )
        self.assertIn("Tracked 1", after.stdout)

    def test_tomorrow_snooze_uses_explicit_due_modifier(self) -> None:
        uuid = "88888888-0000-0000-0000-000000000000"
        self.task(uuid, "tomorrow task", FIXED_NOW)

        self.run_script("taskwarrior_snooze_task.sh", uuid, "765433", "tomorrow")

        self.assertIn(
            f"task rc.hooks:off rc.confirmation:no {uuid} modify due:due+1d",
            self.calls(),
        )

    def test_channel_failure_falls_back_to_default_channel(self) -> None:
        now = FIXED_NOW
        self.task("a" * 36, "window", now + timedelta(minutes=30))

        result = self.run_script(
            "taskwarrior_notify_due_tasks.sh", TNT_TEST_CHANNEL_FAIL="1"
        )

        self.assertIn("Tracked 1", result.stdout)
        self.assertIn("could not create execution notification channel", result.stderr)
        notifications = [
            line for line in self.calls() if line.startswith("termux-notification ")
        ]
        self.assertEqual(1, len(notifications))
        self.assertNotIn("--channel ", notifications[0])

    def test_dismissed_notification_returns_on_next_scan(self) -> None:
        now = FIXED_NOW
        self.task("b" * 36, "window", now + timedelta(minutes=30))

        self.run_script("taskwarrior_notify_due_tasks.sh")
        state_file = self.state_dir / "active-notifications"
        notification_id = state_file.read_text().split("\t", 1)[0]
        self.run_script("taskwarrior_forget_notification.sh", notification_id)
        self.run_script("taskwarrior_notify_due_tasks.sh")

        notifications = [
            line for line in self.calls() if line.startswith("termux-notification ")
        ]
        self.assertEqual(2, len(notifications))

    def test_duration_and_delta_formatting_are_deterministic(self) -> None:
        fake_termuxgui = types.ModuleType("termuxgui")
        fake_termuxgui.Connection = object
        sys.modules["termuxgui"] = fake_termuxgui
        try:
            spec = importlib.util.spec_from_file_location(
                "taskwarrior_gui", SCRIPTS / "taskwarrior_gui.py"
            )
            self.assertIsNotNone(spec)
            self.assertIsNotNone(spec.loader)
            gui = importlib.util.module_from_spec(spec)
            sys.modules["taskwarrior_gui"] = gui
            spec.loader.exec_module(gui)
            self.assertEqual(timedelta(minutes=10), gui.parse_iso_duration("PT10M"))
            self.assertIsNone(gui.parse_iso_duration("not-a-duration"))
            self.assertEqual("1h 5m", gui.format_delta(timedelta(hours=1, minutes=5)))
        finally:
            sys.modules.pop("taskwarrior_gui", None)
            sys.modules.pop("termuxgui", None)

    def test_shared_formatting_module_contract(self) -> None:
        self.assertEqual("a b", clean_text("  a   b  "))
        self.assertEqual(timedelta(minutes=10), parse_iso_duration("PT10M"))
        self.assertIsNone(parse_iso_duration("invalid"))
        self.assertEqual("1h 5m", format_delta(timedelta(hours=1, minutes=5)))
        self.assertIsNotNone(parse_task_date("20260812T130000Z"))

    def test_shared_policy_assigns_buckets_and_priority(self) -> None:
        now = FIXED_NOW
        records = [
            {"name": "overdue", "due": now - timedelta(hours=3), "urgency": 9},
            {"name": "window", "due": now + timedelta(minutes=30), "urgency": 1},
            {"name": "active", "due": now - timedelta(minutes=30), "urgency": 1},
        ]
        self.assertEqual("overdue", reminder_bucket(records[0]["due"], now, 2, 2))
        self.assertEqual("window", reminder_bucket(records[1]["due"], now, 2, 2))
        selected = select_priority(
            records,
            2,
            due_key=lambda record: record["due"],
            urgency_key=lambda record: record["urgency"],
            bucket_key=lambda record: "window" if record["name"] != "overdue" else "overdue",
            active_key=lambda record: record["name"] == "active",
        )
        self.assertEqual(["active", "window"], [record["name"] for record in selected])

    def test_shared_domain_models_are_typed_and_immutable(self) -> None:
        task = TaskRecord("abc", FIXED_NOW, tags=("next",), started=True)
        reminder = Reminder("window", task.uuid, "title", "content", "start", "Start", task.due)
        self.assertTrue(task.started)
        self.assertEqual(("next",), task.tags)
        self.assertEqual("window", reminder.bucket)
        with self.assertRaises(AttributeError):
            task.uuid = "changed"  # type: ignore[misc]

    def test_taskwarrior_adapter_exports_pending_tasks_hookless(self) -> None:
        uuid = "14141414-0000-0000-0000-000000000000"
        self.task(uuid, "adapter task", FIXED_NOW + timedelta(minutes=30))
        environment = self._env()
        tasks = export_pending(
            str(self.bin_dir / "task"), FIXED_NOW, 2, env=environment
        )
        self.assertEqual(uuid, tasks[0]["uuid"])
        self.assertIn("rc.hooks:off", self.export_calls_file.read_text())

    def test_taskwarrior_adapter_reports_invalid_export(self) -> None:
        bad_task = self.bin_dir / "bad-task"
        self._write_executable(
            bad_task,
            "#!/usr/bin/env bash\nprintf 'not json'\n",
        )
        with self.assertRaisesRegex(TaskwarriorCommandError, "valid JSON"):
            export_pending(str(bad_task), FIXED_NOW, 2)

    def test_taskwarrior_adapter_normalizes_export_records(self) -> None:
        raw = {
            "uuid": "17171717-0000-0000-0000-000000000000",
            "due": "20260812T140000",
            "description": "  normalized   task ",
            "project": "work",
            "tags": ["next", "focus"],
            "duration": "PT10M",
            "urgency": "4.5",
            "start": "20260812T130000",
        }
        task = normalize_task(raw)
        self.assertIsNotNone(task)
        assert task is not None
        self.assertEqual("normalized task", task.description)
        self.assertEqual(("next", "focus"), task.tags)
        self.assertEqual(timedelta(minutes=10), task.duration)
        self.assertTrue(task.started)
        self.assertEqual(1, len(normalize_tasks([raw, {"description": "missing due"}])))

    def test_shared_reminder_builder_matches_display_contract(self) -> None:
        tasks = [
            TaskRecord(
                "18181818-0000-0000-0000-000000000000",
                FIXED_NOW + timedelta(minutes=30),
                description="planned",
                project="work",
                tags=("next",),
                duration=timedelta(minutes=10),
            ),
            TaskRecord(
                "19191919-0000-0000-0000-000000000000",
                FIXED_NOW - timedelta(minutes=30),
                description="active",
                started=True,
            ),
        ]
        reminders = build_reminders(tasks, FIXED_NOW, 2, 2, 5)
        self.assertEqual(
            ["active", "planned"],
            [item.title.split(" | ")[-1] for item in reminders],
        )
        self.assertIn("13:20 - 13:30", reminders[1].title)
        self.assertIn("SOON", reminders[1].content)

    def test_shared_state_preserves_manifest_and_snooze_contracts(self) -> None:
        manifest = self.state_dir / "active-notifications"
        write_manifest(
            manifest,
            [ManifestEntry("100", "uuid-a", "finger-a"), ManifestEntry("200", "uuid-b", "finger-b")],
        )
        remove_manifest_id(manifest, "100")
        self.assertEqual(
            [ManifestEntry("200", "uuid-b", "finger-b")], read_manifest(manifest)
        )

        snoozes = self.state_dir / "snoozed-tasks"
        upsert_snooze(snoozes, "uuid-a", 200)
        upsert_snooze(snoozes, "uuid-b", 400)
        self.assertEqual({"uuid-b": 400}, read_snoozes(snoozes, 200))
        remove_snooze(snoozes, "uuid-b")
        self.assertEqual({"uuid-a": 200}, read_snoozes(snoozes, 0))

    def test_android_adapter_builds_termux_api_commands(self) -> None:
        android = Android(
            notification_bin=str(self.bin_dir / "termux-notification"),
            notification_remove_bin=str(self.bin_dir / "termux-notification-remove"),
            channel_bin=str(self.bin_dir / "termux-notification-channel"),
            toast_bin=str(self.bin_dir / "termux-toast"),
            env=self._env(),
        )
        android.create_channel("window", "Window")
        android.notify("--id", "100", "--title", "Task")
        android.remove_notification("100")
        android.toast("done")
        calls = self.calls()
        self.assertIn("termux-notification-channel window Window", calls)
        self.assertIn("termux-notification --id 100 --title Task", calls)
        self.assertIn("termux-notification-remove 100", calls)
        self.assertIn("termux-toast done", calls)

    def test_android_adapter_reports_termux_api_failure(self) -> None:
        failing = self.bin_dir / "failing-termux"
        self._write_executable(failing, "#!/usr/bin/env bash\necho failed >&2\nexit 7\n")
        with self.assertRaisesRegex(AndroidCommandError, "failed"):
            Android(notification_bin=str(failing)).notify("--id", "100")

    def test_action_plans_are_hookless_and_state_aware(self) -> None:
        uuid = "15151515-0000-0000-0000-000000000000"
        start = plan_task_action("start", uuid, "pending")
        self.assertEqual(ActionStatus.READY, start.status)
        self.assertEqual(
            ("rc.hooks:off", "rc.confirmation:no", uuid, "start"), start.task_args
        )
        self.assertEqual(
            ActionStatus.ALREADY_SATISFIED,
            plan_task_action("start", uuid, "pending", started=True).status,
        )
        self.assertEqual(
            ActionStatus.STALE,
            plan_task_action("done", uuid, "completed").status,
        )
        modify = plan_due_modifier(uuid, "due:due+1d", "pending")
        self.assertEqual("modify", modify.action)
        self.assertEqual("due:due+1d", modify.task_args[-1])

    def test_jot_integration_reports_disabled_missing_success_and_failure(self) -> None:
        uuid = "16161616-0000-0000-0000-000000000000"
        self.assertEqual(
            IntegrationStatus.DISABLED,
            JotIntegration(enabled=False).run("start", uuid).status,
        )
        self.assertEqual(
            IntegrationStatus.MISSING,
            JotIntegration(binary=str(self.bin_dir / "missing-jot")).run("start", uuid).status,
        )

        success = self.bin_dir / "jot-success"
        self._write_executable(success, "#!/usr/bin/env bash\nprintf 'logged'\n")
        result = JotIntegration(binary=str(success), enabled=True).run("start", uuid)
        self.assertEqual(IntegrationStatus.OK, result.status)
        self.assertEqual("logged", result.output)

        failure = self.bin_dir / "jot-failure"
        self._write_executable(failure, "#!/usr/bin/env bash\necho 'jot failed' >&2\nexit 3\n")
        result = JotIntegration(binary=str(failure)).run("stop", uuid)
        self.assertEqual(IntegrationStatus.FAILED, result.status)
        self.assertEqual("jot failed", result.output)

    def test_completed_done_action_clears_stale_notification_without_mutation(self) -> None:
        uuid = "dddddddd-0000-0000-0000-000000000000"
        self.task_status = "completed"
        self.run_script(
            "taskwarrior_complete_task.sh",
            uuid,
            "123456",
            TNT_TEST_UUID=uuid,
        )
        calls = self.calls()
        self.assertFalse(any(line.startswith("task ") for line in calls))
        self.assertIn("termux-notification-remove 123456", calls)
        self.assertIn("termux-toast " + uuid[:8] + " already completed; reminder cleared", calls)

    def test_start_and_stop_are_idempotent(self) -> None:
        uuid = "eeeeeeee-0000-0000-0000-000000000000"
        self.task_status = "pending"
        self.task_data = [{"uuid": uuid, "status": "pending"}]
        self.task_started = True
        self.run_script(
            "taskwarrior_start_stop_task.sh", "start", uuid, "1", TNT_TEST_UUID=uuid
        )
        self.task_started = False
        self.run_script(
            "taskwarrior_start_stop_task.sh", "stop", uuid, "2", TNT_TEST_UUID=uuid
        )
        calls = self.calls()
        self.assertFalse(any(line.startswith("task ") for line in calls))
        self.assertIn("termux-toast " + uuid[:8] + " already active", calls)
        self.assertIn("termux-toast " + uuid[:8] + " already stopped", calls)

    def test_snooze_expires_across_midnight(self) -> None:
        uuid = "55555555-0000-0000-0000-000000000000"
        local_tz = timezone(timedelta(hours=3))
        self.task(uuid, "midnight snooze", datetime(2026, 8, 13, 0, 15, tzinfo=local_tz))

        self.run_script(
            "taskwarrior_snooze_task.sh",
            uuid,
            "765436",
            "1h",
            TW_TEST_NOW="2026-08-12T23:30:00+03:00",
        )
        before = self.run_script(
            "taskwarrior_notify_due_tasks.sh",
            TW_TEST_NOW="2026-08-13T00:15:00+03:00",
        )
        self.assertIn("Tracked 0", before.stdout)

        after = self.run_script(
            "taskwarrior_notify_due_tasks.sh",
            TW_TEST_NOW="2026-08-13T00:31:00+03:00",
        )
        self.assertIn("Tracked 1", after.stdout)

    def test_pending_actions_complete_start_and_stop_tasks(self) -> None:
        done_uuid = "44444444-0000-0000-0000-000000000000"
        self.task_data = [{"uuid": done_uuid, "status": "pending"}]
        self.run_script("taskwarrior_complete_task.sh", done_uuid, "1001")
        self.assertIn(
            f"task rc.hooks:off rc.confirmation:no {done_uuid} done", self.calls()
        )

        start_uuid = "33333333-0000-0000-0000-000000000000"
        self.calls_file.write_text("")
        self.task_data = [{"uuid": start_uuid, "status": "pending"}]
        self.task_started = False
        self.run_script("taskwarrior_start_stop_task.sh", "start", start_uuid, "1002")
        self.assertIn(
            f"task rc.hooks:off rc.confirmation:no {start_uuid} start", self.calls()
        )

        stop_uuid = "22222222-0000-0000-0000-000000000000"
        self.calls_file.write_text("")
        self.task_data = [{"uuid": stop_uuid, "status": "pending"}]
        self.task_started = True
        self.run_script("taskwarrior_start_stop_task.sh", "stop", stop_uuid, "1003")
        self.assertIn(
            f"task rc.hooks:off rc.confirmation:no {stop_uuid} stop", self.calls()
        )

    def test_stale_start_and_stop_actions_clear_notifications(self) -> None:
        uuid = "12121212-0000-0000-0000-000000000000"
        self.task_status = "deleted"
        self.run_script("taskwarrior_start_stop_task.sh", "start", uuid, "2001")
        self.run_script("taskwarrior_start_stop_task.sh", "stop", uuid, "2002")
        calls = self.calls()
        self.assertFalse(any(line.startswith("task ") for line in calls))
        self.assertIn("termux-notification-remove 2001", calls)
        self.assertIn("termux-notification-remove 2002", calls)

    def test_start_stop_and_modify_snooze_failures_are_reported(self) -> None:
        uuid = "13131313-0000-0000-0000-000000000000"
        self.task_data = [{"uuid": uuid, "status": "pending"}]
        failed_start = self.run_script(
            "taskwarrior_start_stop_task.sh",
            "start",
            uuid,
            "3001",
            check=False,
            TNT_TEST_ACTION_FAIL="1",
        )
        self.assertNotEqual(0, failed_start.returncode)
        self.assertIn("task start failed", failed_start.stdout)

        self.calls_file.write_text("")
        failed_snooze = self.run_script(
            "taskwarrior_snooze_task.sh",
            uuid,
            "3002",
            "tomorrow",
            check=False,
            TNT_TEST_ACTION_FAIL="1",
        )
        self.assertNotEqual(0, failed_snooze.returncode)
        self.assertIn("task snooze failed", failed_snooze.stdout)

    def test_snooze_replacement_keeps_one_current_entry(self) -> None:
        uuid = "66666666-0000-0000-0000-000000000000"
        self.task(uuid, "replace snooze", datetime(2026, 8, 12, 15, 0))

        self.run_script(
            "taskwarrior_snooze_task.sh",
            uuid,
            "765434",
            "1h",
            TW_TEST_NOW="2026-08-12T13:00:00+00:00",
        )
        self.run_script(
            "taskwarrior_snooze_task.sh",
            uuid,
            "765435",
            "1h",
            TW_TEST_NOW="2026-08-12T14:00:00+00:00",
        )

        entries = (self.state_dir / "snoozed-tasks").read_text().splitlines()
        self.assertEqual(1, len(entries))
        self.assertTrue(entries[0].startswith(uuid + "\t"))
        self.assertGreater(int(entries[0].split("\t", 1)[1]), 0)

    def test_missing_task_snooze_clears_notification(self) -> None:
        uuid = "ffffffff-0000-0000-0000-000000000000"
        self.task_status = "missing"
        self.run_script(
            "taskwarrior_snooze_task.sh",
            uuid,
            "654321",
            "tomorrow",
            TNT_TEST_UUID=uuid,
        )
        calls = self.calls()
        self.assertFalse(any(line.startswith("task ") for line in calls))
        self.assertIn("termux-notification-remove 654321", calls)

    def test_task_action_failure_is_reported(self) -> None:
        uuid = "11111111-0000-0000-0000-000000000000"
        self.task_status = "pending"
        self.task_data = [{"uuid": uuid, "status": "pending"}]
        result = self.run_script(
            "taskwarrior_complete_task.sh",
            uuid,
            "987654",
            check=False,
            TNT_TEST_UUID=uuid,
            TNT_TEST_ACTION_FAIL="1",
        )
        self.assertNotEqual(0, result.returncode)
        self.assertIn("completion failed", result.stdout)
        self.assertIn("completion failed", "\n".join(self.calls()))

    def test_common_snapshot_reports_missing_status(self) -> None:
        uuid = "2" * 36
        env = self._env(TNT_TEST_STATUS="missing")
        command = (
            "source scripts/taskwarrior_tnt_common.sh; "
            f"tnt_load_task_snapshot /tmp/unused '{self.bin_dir / 'task'}' >/dev/null; "
            "printf '%s' \"$TNT_TASK_STATUS\""
        )
        # Use the actual task path as the helper's first argument.
        command = (
            "source scripts/taskwarrior_tnt_common.sh; "
            f"tnt_load_task_snapshot '{self.bin_dir / 'task'}' '{uuid}'; "
            "printf '%s' \"$TNT_TASK_STATUS\""
        )
        result = subprocess.run(
            ["bash", "-c", command], cwd=ROOT, env=env, capture_output=True, text=True
        )
        self.assertEqual(0, result.returncode)
        self.assertEqual("missing", result.stdout)


if __name__ == "__main__":
    unittest.main()
