"""Original MQTT admission persists the local hint, not phone-granted access."""
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import mqtt_bridge
from agent_execution_harness import COLLABORATION_WORKSPACE_RESULT
from phone_member_recall import MARKER, OPTION
from test_mqtt_codex_steering import _ImmediateThread, _SteeringTaskManager, _SteeringCodexServer


class MqttMemberRecallTest(unittest.TestCase):
    def test_final_encrypt_recipient_is_bound_to_the_authorized_pair(self):
        peer = {"client_route_id": "phone", "identity_fingerprint": "phone-key",
                "local_identity_fingerprint": "desktop-key", "link_secret": "link-one"}
        binding = mqtt_bridge._receipt_binding_for_client(peer)
        self.enterContext(patch.object(mqtt_bridge, "_wire_client", return_value=peer))
        self.enterContext(patch.object(mqtt_bridge, "_topics_for_client", return_value=SimpleNamespace(send="fixture")))
        self.enterContext(patch("agent_worker_routing.recipient_allowed", return_value=True))
        publish = self.enterContext(patch.object(mqtt_bridge, "_publish_to_registered_client",
            return_value=SimpleNamespace(rc=mqtt_bridge.mqtt.MQTT_ERR_SUCCESS, mid=1)))
        def send():
            return mqtt_bridge._publish_phone_payload(object(), {"_client_route_id":"phone"},
                {"type":"collaboration_recall_request"}, durable=False, recall_recipient=binding)
        self.assertTrue(send())
        peer["link_secret"] = "link-two"
        self.assertFalse(send())
        publish.assert_called_once()

    def test_authenticated_admission_and_unmarked_control(self):
        root = Path(self.enterContext(tempfile.TemporaryDirectory()))
        peer = {"client_route_id": "client-1", "identity_fingerprint": "fixture-fingerprint"}
        self.enterContext(patch.object(mqtt_bridge, "get_client", return_value=peer))
        server, manager = _SteeringCodexServer(), _SteeringTaskManager()
        manager.prior.status = "completed"
        self.enterContext(patch.object(mqtt_bridge, "agent_task_manager", manager))
        self.enterContext(patch.object(mqtt_bridge, "_codex_server", return_value=server))
        self.enterContext(patch.object(mqtt_bridge, "codex_task_callbacks", {}))
        self.enterContext(patch.object(mqtt_bridge, "_enqueue_task_event"))
        self.enterContext(patch.object(mqtt_bridge, "_publish_or_queue_task_result"))
        self.enterContext(patch.object(mqtt_bridge.threading, "Thread", _ImmediateThread))
        self.enterContext(patch("agent_latency_hooks.trace_stage"))
        self.enterContext(patch("agent_gateway._find_codex_desktop_cli", return_value="codex"))
        self.enterContext(patch("task_workspace.task_workspace", return_value=root))
        self.enterContext(patch("agent_conversation_sessions.agent_conversation_sessions"))
        create = self.enterContext(patch.object(manager, "create_external", wraps=manager.create_external))
        for number, options in enumerate(({OPTION: True}, {}, {OPTION: True, "agent_team_message": True},
                                          {OPTION: True, "agent_team_message": "TrUe"})):
            payload = {"type": "text", "contact_id": "codex", "agent_id": "codex", **options,
                "client_route_id": "client-1", "client_message_id": str(700 + number),
                "task_id": f"isolated-{number}", "turn_id": "shared-root", "conversation_id": "group",
                "execution_mode": "auto_complete", "result_contract": COLLABORATION_WORKSPACE_RESULT,
                "team_id": "fixture-team", "agent_instance_id": f"instance-{number}", "attachments": []}
            if not options:
                manager.prior.status = "running"
                manager.prior.conversation_id = "client:identity:fixture-fingerprint:group:agent-instance:instance-1"
                manager.prior.request_snapshot = {MARKER: {"team":"fixture-team", "member":"instance-1"}}
            mqtt_bridge._start_remote_agent_task(SimpleNamespace(), {"scheme":"signal", "_client_route_id":"client-1"},
                payload, [], "Review the assignment", "text")
            snapshot = create.call_args.kwargs["request_snapshot"]
            self.assertEqual(number == 0, MARKER in snapshot)
            self.assertNotIn(OPTION, snapshot["options"])
            self.assertEqual("auto_complete", snapshot["options"]["execution_mode"])
            self.assertEqual(f"instance-{number}", snapshot["options"]["agent_instance_id"])
            call = server.start_calls[-1][1]
            self.assertEqual(number == 0, call.get("isolate_member", False))
            self.assertEqual(f"client:identity:fixture-fingerprint:group:agent-instance:instance-{number}", call["conversation_id"])
        self.assertEqual([], server.steers)
