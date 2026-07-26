from __future__ import annotations

import unittest
from types import SimpleNamespace
from unittest.mock import patch

import evolution_manager
import mqtt_bridge
from pairing_access import grant_for_executor


class FakeStore:
    def __init__(self, tasks):
        self.tasks = tasks

    def list(self, limit=100):
        return self.tasks[:limit]


class FakeManager:
    def __init__(self, tasks):
        self.store = FakeStore(tasks)
        self.tasks = {task.task_id: task for task in tasks}
        self.cancelled = []

    def require(self, task_id):
        return self.tasks[task_id]

    def cancel(self, task_id):
        self.cancelled.append(task_id)
        return self.tasks[task_id]


def fake_task(task_id, route_id):
    return SimpleNamespace(
        task_id=task_id,
        client_route_id=route_id,
        public=lambda: {
            "task_id": task_id,
            "status": "waiting_approval",
            "execution_target": "desktop",
        },
    )


class MqttEvolutionRoutingTests(unittest.TestCase):
    def setUp(self):
        self.published = []
        self.client = {
            "client_route_id": "route-a",
            "access": grant_for_executor(True),
        }
        self.patches = [
            patch.object(mqtt_bridge, "desktop_id", return_value="desktop-test"),
            patch.object(mqtt_bridge, "desktop_name", return_value="Test Desktop"),
            patch.object(
                mqtt_bridge,
                "_publish_phone_payload",
                side_effect=lambda _mqtt, _wire, payload, **_kwargs:
                    self.published.append(dict(payload)) or True,
            ),
        ]
        for item in self.patches:
            item.start()

    def tearDown(self):
        for item in reversed(self.patches):
            item.stop()

    def test_snapshot_contains_only_tasks_owned_by_requesting_phone(self):
        manager = FakeManager([
            fake_task("owned", "route-a"),
            fake_task("other-phone", "route-b"),
            fake_task("desktop-local", ""),
        ])
        with patch.object(evolution_manager, "evolution_manager", return_value=manager):
            mqtt_bridge._publish_evolution_snapshot(object(), self.client)

        self.assertEqual(["owned"], [
            task["task_id"] for task in self.published[-1]["tasks"]
        ])
        self.assertEqual("desktop-test", self.published[-1]["desktop_id"])

    def test_phone_cannot_control_another_phone_candidate(self):
        manager = FakeManager([fake_task("other-phone", "route-b")])
        with (
            patch.object(evolution_manager, "evolution_manager", return_value=manager),
            patch.object(mqtt_bridge, "has_full_executor", return_value=True),
        ):
            handled = mqtt_bridge._route_evolution_payload(
                object(),
                self.client,
                {
                    "type": mqtt_bridge.EVOLUTION_TASK_CANCEL_TYPE,
                    "task_id": "other-phone",
                },
            )

        self.assertTrue(handled)
        self.assertEqual([], manager.cancelled)
        self.assertEqual("task_owner_mismatch", self.published[-1]["error_code"])
        self.assertEqual("desktop-test", self.published[-1]["desktop_id"])

    def test_restricted_pairing_receives_a_named_rejection_event(self):
        restricted = {
            **self.client,
            "access": grant_for_executor(False),
        }

        handled = mqtt_bridge._route_evolution_payload(
            object(),
            restricted,
            {"type": mqtt_bridge.EVOLUTION_TASK_LIST_REQUEST_TYPE},
        )

        self.assertTrue(handled)
        self.assertEqual("desktop_executor_required", self.published[-1]["error_code"])
        self.assertEqual("desktop-test", self.published[-1]["desktop_id"])
        self.assertEqual("Test Desktop", self.published[-1]["desktop_name"])

    def test_local_evolution_events_reach_only_full_executor_pairings(self):
        restricted = {
            "client_route_id": "route-b",
            "access": grant_for_executor(False),
        }
        with (
            patch.object(mqtt_bridge, "client", object()),
            patch.object(mqtt_bridge, "list_clients", return_value=[self.client, restricted]),
        ):
            result = mqtt_bridge.publish_evolution_task_event_all({
                "event": "candidate_ready",
                "task": {"task_id": "desktop-local"},
            })

        self.assertEqual({"ok": True, "published": 1}, result)
        self.assertEqual(1, len(self.published))
        self.assertEqual("candidate_ready", self.published[0]["event"])


if __name__ == "__main__":
    unittest.main()
