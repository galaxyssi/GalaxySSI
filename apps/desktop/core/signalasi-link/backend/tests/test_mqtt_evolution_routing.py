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

    def test_snapshot_never_leaves_desktop(self):
        manager = FakeManager([
            fake_task("owned", "route-a"),
            fake_task("other-phone", "route-b"),
            fake_task("desktop-local", ""),
        ])
        with patch.object(evolution_manager, "evolution_manager", return_value=manager):
            mqtt_bridge._publish_evolution_snapshot(object(), self.client)

        self.assertEqual([], self.published)

    def test_phone_cannot_control_private_evolution(self):
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
        self.assertEqual([], self.published)

    def test_restricted_pairing_does_not_receive_private_rejection_details(self):
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
        self.assertEqual([], self.published)

    def test_local_evolution_events_never_reach_pairings(self):
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

        self.assertEqual({"ok": True, "published": 0, "code": "local_only"}, result)
        self.assertEqual([], self.published)

    def test_transport_policy_blocks_all_private_global_payload_classes(self):
        samples = [
            {"type": "evolution_task_event"},
            {"type": "memory_evolution_candidate"},
            {"type": "global_agent_event"},
            {"type": "text", "conversation_id": "global-research:task-1"},
            {"type": "text", "task_kind": "self_evolution"},
        ]

        self.assertTrue(all(mqtt_bridge._local_only_transport_payload(item) for item in samples))
        self.assertFalse(mqtt_bridge._local_only_transport_payload({
            "type": "text",
            "conversation_id": "user-conversation",
        }))


if __name__ == "__main__":
    unittest.main()
