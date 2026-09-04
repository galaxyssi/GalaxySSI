from __future__ import annotations

import unittest
from types import SimpleNamespace
from unittest.mock import patch

import mqtt_bridge


class _TaskManager:
    def __init__(self, task) -> None:
        self.task = task

    def get(self, task_id: str):
        return self.task if task_id == self.task.task_id else None


class _ApprovalServer:
    def __init__(self, expected_hash: str) -> None:
        self.expected_hash = expected_hash
        self.calls: list[dict] = []

    def resolve_approval(self, **values) -> None:
        if values["action_hash"] != self.expected_hash:
            raise ValueError("Action hash does not match the pending request")
        self.calls.append(dict(values))


class _PermissionPolicy:
    def __init__(self) -> None:
        self.calls: list[dict] = []

    def record(self, **values):
        self.calls.append(dict(values))


class MqttAgentApprovalTests(unittest.TestCase):
    def setUp(self) -> None:
        self.action_hash = "a" * 64
        self.task = SimpleNamespace(
            task_id="task-1",
            agent_id="codex",
            client_route_id="phone-route-1",
            client_conversation_id="conversation-1",
            client_turn_id="turn-1",
            contact_id="codex",
            source_message_id="message-1",
        )
        self.payload = {
            "task_id": self.task.task_id,
            "client_route_id": self.task.client_route_id,
            "conversation_id": self.task.client_conversation_id,
            "turn_id": self.task.client_turn_id,
            "approval_id": "approval-12345678",
            "action_hash": self.action_hash,
            "source_message_id": self.task.source_message_id,
            "decision_scope": "allow_once",
            "approved": True,
        }
        self.permission_policy = _PermissionPolicy()
        self.policy_patch = patch.object(
            mqtt_bridge,
            "tool_permission_policy",
            self.permission_policy,
        )
        self.policy_patch.start()
        self.addCleanup(self.policy_patch.stop)

    def test_exact_paired_task_approval_resumes_codex(self) -> None:
        server = _ApprovalServer(self.action_hash)
        with (
            patch.object(mqtt_bridge, "agent_task_manager", _TaskManager(self.task)),
            patch.object(mqtt_bridge, "codex_app_server", server),
        ):
            result = mqtt_bridge._resolve_agent_task_approval(
                self.payload,
                client_route_id=self.task.client_route_id,
                contact_id=self.task.contact_id,
            )

        self.assertTrue(result["resolved"])
        self.assertEqual("", result["error"])
        self.assertEqual(
            [{
                "task_id": self.task.task_id,
                "approval_id": self.payload["approval_id"],
                "action_hash": self.action_hash,
                "approved": True,
            }],
            server.calls,
        )
        self.assertEqual("allow_once", self.permission_policy.calls[0]["choice"])

    def test_task_identity_mismatch_never_reaches_codex(self) -> None:
        for field, value in (
            ("client_route_id", "another-phone"),
            ("contact_id", "another-contact"),
        ):
            with self.subTest(field=field):
                server = _ApprovalServer(self.action_hash)
                options = {
                    "client_route_id": self.task.client_route_id,
                    "contact_id": self.task.contact_id,
                }
                options[field] = value
                with (
                    patch.object(mqtt_bridge, "agent_task_manager", _TaskManager(self.task)),
                    patch.object(mqtt_bridge, "codex_app_server", server),
                ):
                    result = mqtt_bridge._resolve_agent_task_approval(
                        self.payload,
                        **options,
                    )
                self.assertFalse(result["resolved"])
                self.assertIn("does not match", result["error"])
                self.assertEqual([], server.calls)

        changed_source = dict(self.payload, source_message_id="another-message")
        server = _ApprovalServer(self.action_hash)
        with (
            patch.object(mqtt_bridge, "agent_task_manager", _TaskManager(self.task)),
            patch.object(mqtt_bridge, "codex_app_server", server),
        ):
            result = mqtt_bridge._resolve_agent_task_approval(
                changed_source,
                client_route_id=self.task.client_route_id,
                contact_id=self.task.contact_id,
            )
        self.assertFalse(result["resolved"])
        self.assertEqual([], server.calls)

        for field, value in (
            ("conversation_id", "another-conversation"),
            ("turn_id", "another-turn"),
            ("task_id", "another-task"),
        ):
            with self.subTest(field=field):
                server = _ApprovalServer(self.action_hash)
                changed = dict(self.payload, **{field: value})
                with (
                    patch.object(mqtt_bridge, "agent_task_manager", _TaskManager(self.task)),
                    patch.object(mqtt_bridge, "codex_app_server", server),
                ):
                    result = mqtt_bridge._resolve_agent_task_approval(
                        changed,
                        client_route_id=self.task.client_route_id,
                        contact_id=self.task.contact_id,
                    )
                self.assertFalse(result["resolved"])
                self.assertEqual([], server.calls)

    def test_changed_action_hash_is_rejected(self) -> None:
        server = _ApprovalServer(self.action_hash)
        changed = dict(self.payload, action_hash="b" * 64)
        with (
            patch.object(mqtt_bridge, "agent_task_manager", _TaskManager(self.task)),
            patch.object(mqtt_bridge, "codex_app_server", server),
        ):
            result = mqtt_bridge._resolve_agent_task_approval(
                changed,
                client_route_id=self.task.client_route_id,
                contact_id=self.task.contact_id,
            )

        self.assertFalse(result["resolved"])
        self.assertIn("hash", result["error"].lower())
        self.assertEqual([], server.calls)

    def test_scope_and_boolean_must_describe_the_same_decision(self) -> None:
        server = _ApprovalServer(self.action_hash)
        changed = dict(
            self.payload,
            decision_scope="deny_always",
            approved=True,
        )
        with (
            patch.object(mqtt_bridge, "agent_task_manager", _TaskManager(self.task)),
            patch.object(mqtt_bridge, "codex_app_server", server),
        ):
            result = mqtt_bridge._resolve_agent_task_approval(
                changed,
                client_route_id=self.task.client_route_id,
                contact_id=self.task.contact_id,
            )

        self.assertFalse(result["resolved"])
        self.assertIn("does not match", result["error"])
        self.assertEqual([], server.calls)

    def test_permanent_denial_is_applied_and_saved(self) -> None:
        server = _ApprovalServer(self.action_hash)
        denied = dict(
            self.payload,
            decision_scope="deny_always",
            approved=False,
        )
        with (
            patch.object(mqtt_bridge, "agent_task_manager", _TaskManager(self.task)),
            patch.object(mqtt_bridge, "codex_app_server", server),
        ):
            result = mqtt_bridge._resolve_agent_task_approval(
                denied,
                client_route_id=self.task.client_route_id,
                contact_id=self.task.contact_id,
            )

        self.assertTrue(result["resolved"])
        self.assertFalse(server.calls[0]["approved"])
        self.assertEqual("deny_always", self.permission_policy.calls[0]["choice"])


if __name__ == "__main__":
    unittest.main()
