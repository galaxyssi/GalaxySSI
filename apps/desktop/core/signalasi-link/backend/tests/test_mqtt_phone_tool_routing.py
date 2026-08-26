from __future__ import annotations

import json
import tempfile
import time
import unittest
import uuid
from pathlib import Path
from unittest.mock import patch

import link_protocol
import mqtt_bridge
import pairing_state
import phone_tool_broker
import desktop_control
from peer_chat_store import PeerChatStore


class FakeInfo:
    def __init__(self, mid: int = 1, rc: int = 0) -> None:
        self.mid = mid
        self.rc = rc


class FakeMqtt:
    def is_connected(self) -> bool:
        return True


class FakeMessage:
    def __init__(self, paired_client: dict) -> None:
        topics = link_protocol.LinkTopics(
            paired_client["link_secret"],
            paired_client["local_identity_fingerprint"],
            paired_client["identity_fingerprint"],
        )
        self.topic = topics.receive
        inner = (
            '{"scheme":"signal","from":"'
            + paired_client["signal_name"]
            + '","body":"'
            + uuid.uuid4().hex
            + '"}'
        )
        self.payload = link_protocol.seal_wire_packet(
            inner,
            paired_client["link_secret"],
        ).encode("ascii")


class MqttPhoneToolRoutingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.state_patch = patch.object(
            pairing_state,
            "STATE_PATH",
            Path(self.temp.name) / "registry.json",
        )
        self.state_patch.start()
        with mqtt_bridge.phone_tool_sessions_lock:
            mqtt_bridge.phone_tool_sessions.clear()

        self.mqtt = FakeMqtt()
        self.desktop_id = "desktop_test"
        self.manifest_hash = phone_tool_broker.compute_manifest_hash(
            {"revision": 1, "tools": ["signalasi.workspace.file.read.text"]}
        )
        self.published: list[tuple[dict, dict, str]] = []
        self.decrypted: dict = {}
        self.agent_starts: list[tuple] = []
        self.publish_phone_payload_patch = patch.object(mqtt_bridge, "_publish_phone_payload", return_value=True)
        self.publish_phone_payload = self.publish_phone_payload_patch.start()
        self.patches = [
            patch.object(mqtt_bridge, "desktop_id", return_value=self.desktop_id),
            patch.object(mqtt_bridge, "claim_message", return_value=True),
            patch.object(mqtt_bridge, "complete_message"),
            patch.object(
                mqtt_bridge,
                "decrypt_signal_envelope",
                side_effect=lambda *_args, **_kwargs: self.decrypted,
            ),
            patch.object(
                mqtt_bridge,
                "_publish_to_registered_client",
                side_effect=self._capture_publish,
            ),
            patch.object(
                mqtt_bridge,
                "_start_remote_agent_task",
                side_effect=lambda *args: self.agent_starts.append(args),
            ),
        ]
        for item in self.patches:
            item.start()

        self.first = self._pair_client("first-route", "signalasi:first-phone")
        self.second = self._pair_client("second-route", "signalasi:second-phone")

    def test_phone_development_v2_uses_exact_content_transport(self) -> None:
        source = "def main():\n    print('ok')\n"
        manifest = json.dumps(
            {
                "schema": "signalasi.phone-development-manifest.v2",
                "language": "python",
                "entry_file": "main.py",
                "files": [{"path": "main.py", "content": source}],
            },
            ensure_ascii=False,
        )

        self.assertTrue(mqtt_bridge.requires_exact_content_transport(manifest))
        self.assertFalse(mqtt_bridge.requires_exact_content_transport("ordinary assistant reply"))
        self.assertEqual(source, json.loads(manifest)["files"][0]["content"])

    def test_scalar_and_collection_json_replies_do_not_crash_transport_detection(self) -> None:
        for reply in ("7319", "true", "false", "null", '"done"', "[]", '[{"result":"ok"}]'):
            with self.subTest(reply=reply):
                self.assertFalse(mqtt_bridge.requires_exact_content_transport(reply))

    def test_malformed_manifest_fallback_remains_exact(self) -> None:
        malformed = '{"schema":"signalasi.phone-development-manifest.v2"'
        self.assertTrue(mqtt_bridge.requires_exact_content_transport(malformed))

    def tearDown(self) -> None:
        with mqtt_bridge.phone_tool_sessions_lock:
            mqtt_bridge.phone_tool_sessions.clear()
        for item in reversed(self.patches):
            item.stop()
        self.publish_phone_payload_patch.stop()
        self.state_patch.stop()
        self.temp.cleanup()

    def _pair_client(self, fingerprint: str, signal_name: str) -> dict:
        return pairing_state.record_pairing_success(
            fingerprint=fingerprint,
            remote_name=signal_name,
            client_route_id=link_protocol.new_route_id(),
            display_name=fingerprint,
            platform="android",
            link_secret=link_protocol.new_link_secret(),
            local_identity_fingerprint="d" * 64,
        )

    def _capture_publish(self, _mqttc, paired_client, payload, channel="down", durable=True):
        self.published.append((paired_client, payload, channel))
        return FakeInfo(mid=len(self.published))

    def _deliver(self, paired_client: dict, payload: dict, conversation_id: str = "conversation-1") -> None:
        self.decrypted = link_protocol.make_envelope(
            payload,
            source_id=paired_client["signal_name"],
            target_id=self.desktop_id,
            conversation_id=conversation_id,
        )
        mqtt_bridge.on_message(
            self.mqtt,
            None,
            FakeMessage(paired_client),
        )

    def _start_session(self, paired_client: dict | None = None) -> None:
        now_ms = int(time.time() * 1000)
        self._deliver(
            paired_client or self.first,
            {
                "protocol": phone_tool_broker.PROTOCOL_NAME,
                "version": phone_tool_broker.PROTOCOL_VERSION,
                "type": mqtt_bridge.TOOL_SESSION_START_TYPE,
                "message_id": str(uuid.uuid4()),
                "session_id": "session-1",
                "task_id": "task-1",
                "turn_id": "turn-1",
                "manifest_hash": self.manifest_hash,
                "sequence": 1,
                "sent_at": now_ms,
                "expires_at": now_ms + 60_000,
                "conversation_id": "conversation-1",
                "payload": {"goal": "Inspect selected workspace"},
            },
        )

    def _request_call(self, call_id: str = "call-1", sequence: int = 1) -> dict:
        return mqtt_bridge.request_phone_tool_call(
            "session-1",
            call_id=call_id,
            sequence=sequence,
            tool_id="signalasi.workspace.file.read.text",
            arguments={"path": "src/Main.kt"},
        )

    def test_session_start_binds_request_to_paired_encrypted_control_route(self):
        self._start_session()

        request = self._request_call()

        self.assertIn("session-1", mqtt_bridge.phone_tool_sessions)
        self.assertEqual(phone_tool_broker.REQUEST_TYPE, request["type"])
        paired_client, transport_payload, channel = self.published[-1]
        self.assertEqual(self.first["client_route_id"], paired_client["client_route_id"])
        self.assertEqual("control", channel)
        self.assertEqual(mqtt_bridge.TOOL_CALL_REQUEST_TYPE, transport_payload["type"])
        self.assertEqual("session-1", transport_payload["session_id"])
        self.assertEqual("conversation-1", transport_payload["conversation_id"])
        self.assertNotIn("mqtt_topic", transport_payload)
        self.assertEqual([], self.agent_starts)

    def test_result_from_other_paired_client_cannot_complete_session_call(self):
        self._start_session()
        request = self._request_call()
        response = phone_tool_broker.make_response_envelope(
            request,
            status="succeeded",
            result={"text": "done"},
        )
        transport_result = {**response, "type": mqtt_bridge.TOOL_CALL_RESULT_TYPE}

        self._deliver(self.second, transport_result)
        self.assertEqual(1, mqtt_bridge.phone_tool_sessions["session-1"].broker.pending_count)

        self._deliver(self.first, transport_result, conversation_id="conversation-2")
        self.assertEqual(1, mqtt_bridge.phone_tool_sessions["session-1"].broker.pending_count)

        self._deliver(self.first, transport_result)
        accepted = mqtt_bridge.wait_for_phone_tool_result("session-1", "call-1")
        self.assertEqual("succeeded", accepted["payload"]["status"])
        self.assertEqual({"text": "done"}, accepted["payload"]["result"])

    def test_desktop_and_phone_cancellation_envelopes_are_terminal(self):
        self._start_session()
        self._request_call()

        cancelled = mqtt_bridge.cancel_phone_tool_call("session-1", "call-1", "task stopped")

        self.assertEqual(phone_tool_broker.CANCEL_TYPE, cancelled["type"])
        self.assertEqual(mqtt_bridge.TOOL_CALL_CANCEL_TYPE, self.published[-1][1]["type"])
        self.assertEqual("control", self.published[-1][2])

        request = self._request_call(call_id="call-2", sequence=3)
        phone_cancel = phone_tool_broker.make_cancel_envelope(
            request,
            sequence=4,
            reason="permission revoked",
        )
        self._deliver(
            self.first,
            {**phone_cancel, "type": mqtt_bridge.TOOL_CALL_CANCEL_TYPE},
        )

        result = mqtt_bridge.wait_for_phone_tool_result("session-1", "call-2")
        self.assertEqual("cancelled", result["payload"]["status"])
        self.assertEqual("phone_cancelled", result["payload"]["error"]["code"])

    def test_regular_text_message_still_uses_existing_agent_flow(self):
        self._deliver(
            self.first,
            {
                "type": "text",
                "content": "hello",
                "contact_id": "hermes",
                "client_message_id": str(uuid.uuid4()),
            },
        )

        self.assertEqual(1, len(self.agent_starts))
        self.assertEqual({}, mqtt_bridge.phone_tool_sessions)

    def test_unified_command_executes_and_returns_structured_result(self):
        message_id = str(uuid.uuid4())
        self._deliver(
            self.first,
            {
                "type": "unified_command",
                "command_id": "commands.list",
                "args": {"dry_run": True},
                "contact_id": "system",
                "message_id": message_id,
                "source_message_id": message_id,
            },
        )

        self.assertEqual([], self.agent_starts)
        result_payload = self.publish_phone_payload.call_args_list[-1].args[2]
        self.assertEqual("unified_command_result", result_payload["type"])
        self.assertEqual("commands.list", result_payload["command_id"])
        self.assertEqual("completed", result_payload["command_status"])
        self.assertEqual("completed", result_payload["result"]["status"])
        self.assertEqual(message_id, result_payload["source_message_id"])

    def test_peer_message_is_stored_without_starting_an_agent(self):
        peer_store = PeerChatStore(Path(self.temp.name) / "peer-chat.db")
        message_id = str(uuid.uuid4())
        with patch("peer_chat_store.peer_chat_store", return_value=peer_store):
            self._deliver(
                self.first,
                {
                    "type": mqtt_bridge.PEER_MESSAGE_TYPE,
                    "message_id": message_id,
                    "source_message_id": message_id,
                    "contact_id": self.desktop_id,
                    "content": "Direct device message",
                    "time": time.time(),
                },
            )

        self.assertEqual([], self.agent_starts)
        messages = peer_store.list_messages(self.first["client_route_id"])
        self.assertEqual(1, len(messages))
        self.assertEqual("Direct device message", messages[0]["content"])
        self.assertEqual("inbound", messages[0]["direction"])

    def test_client_revocation_cleans_only_the_calling_phone(self):
        with (
            patch.object(mqtt_bridge, "forget_paired_client_transport", return_value={
                "deleted_peer_messages": 2,
            }) as cleanup,
            patch.object(mqtt_bridge, "remove_peer_signal_session") as remove_session,
            patch.object(mqtt_bridge, "reconcile_mqtt_subscriptions", return_value={
                "ok": True,
                "expected": 4,
            }) as reconcile,
            patch.object(desktop_control, "desktop_control_manager") as control_manager,
        ):
            self._deliver(
                self.first,
                {
                    "type": "client_revoked",
                    "reason": "forgotten_by_client",
                    "message_id": str(uuid.uuid4()),
                },
            )

        cleanup.assert_called_once_with(self.first["client_route_id"], self.mqtt)
        remove_session.assert_called_once_with(self.first["signal_name"], 1)
        control_manager.return_value.revoke_for_client.assert_called_once_with(
            self.first["client_route_id"],
            "pairing_revoked_by_phone",
        )
        reconcile.assert_called_once_with(self.mqtt)
        self.assertIsNone(pairing_state.get_client(self.first["client_route_id"]))
        self.assertIsNotNone(pairing_state.get_client(self.second["client_route_id"]))
        self.assertEqual([], self.agent_starts)

        peer_store = PeerChatStore(Path(self.temp.name) / "remaining-peer-chat.db")
        message_id = str(uuid.uuid4())
        with patch("peer_chat_store.peer_chat_store", return_value=peer_store):
            self._deliver(
                self.second,
                {
                    "type": mqtt_bridge.PEER_MESSAGE_TYPE,
                    "message_id": message_id,
                    "source_message_id": message_id,
                    "contact_id": self.desktop_id,
                    "content": "Remaining phone still connected",
                    "time": time.time(),
                },
            )

        messages = peer_store.list_messages(self.second["client_route_id"])
        self.assertEqual(1, len(messages))
        self.assertEqual("Remaining phone still connected", messages[0]["content"])
        self.assertEqual([], self.agent_starts)

    def test_desktop_peer_message_uses_uuid_transport_id(self):
        peer_store = PeerChatStore(Path(self.temp.name) / "peer-outbound.db")
        with (
            patch.object(mqtt_bridge, "client", self.mqtt),
            patch("peer_chat_store.peer_chat_store", return_value=peer_store),
        ):
            result = mqtt_bridge.publish_peer_message(
                self.first["client_route_id"],
                "Direct reply",
            )

        self.assertTrue(result["ok"])
        uuid.UUID(result["message_id"])
        outbound_payload = self.publish_phone_payload.call_args.args[2]
        self.assertEqual(result["message_id"], outbound_payload["message_id"])
        self.assertEqual([], self.agent_starts)

    def test_wrong_link_target_cannot_create_tool_session(self):
        now_ms = int(time.time() * 1000)
        payload = {
            "type": mqtt_bridge.TOOL_SESSION_START_TYPE,
            "session_id": "session-1",
            "task_id": "task-1",
            "turn_id": "turn-1",
            "manifest_hash": self.manifest_hash,
            "sequence": 1,
            "sent_at": now_ms,
            "expires_at": now_ms + 60_000,
        }
        self.decrypted = link_protocol.make_envelope(
            payload,
            source_id=self.first["signal_name"],
            target_id="some-other-desktop",
        )

        mqtt_bridge.on_message(
            self.mqtt,
            None,
            FakeMessage(self.first),
        )

        self.assertEqual({}, mqtt_bridge.phone_tool_sessions)


if __name__ == "__main__":
    unittest.main()
