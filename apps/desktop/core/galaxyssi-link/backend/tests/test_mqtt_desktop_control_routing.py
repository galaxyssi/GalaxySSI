from __future__ import annotations

import tempfile
import time
import unittest
import uuid
import hashlib
from pathlib import Path
from unittest.mock import patch

import desktop_control
import mqtt_bridge
from pairing_access import grant_for_executor


class ImmediateThread:
    def __init__(self, *, target, **_kwargs) -> None:
        self.target = target

    def start(self) -> None:
        self.target()


class FakeInput:
    def __init__(self) -> None:
        self.calls: list[tuple] = []

    def is_locked(self) -> bool:
        return False

    def click(
        self,
        x: int,
        y: int,
        button: str,
        *,
        source_width: int | None = None,
        source_height: int | None = None,
        target_bounds: dict | None = None,
    ) -> None:
        self.calls.append(("click", x, y, button))

    def type_text(self, value: str) -> None:
        self.calls.append(("type", len(value)))

    def hotkey(self, keys: list[str]) -> None:
        self.calls.append(("hotkey", tuple(keys)))

    def scroll(self, delta: int) -> None:
        self.calls.append(("scroll", delta))


class MqttDesktopControlRoutingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.input = FakeInput()
        signature_key_id = hashlib.sha256(b"mqtt-test-public-key").hexdigest()
        identity = {
            "signer_id": "desktop-test",
            "signature_key_id": signature_key_id,
        }
        self.manager = desktop_control.DesktopControlManager(
            Path(self.temporary.name) / "desktop-control.json",
            screenshot_provider=lambda: {
                "image_mime": "image/jpeg",
                "image_base64": "/9j/2Q==",
                "width": 480,
                "height": 270,
                "original_width": 1920,
                "original_height": 1080,
                "bytes": 4,
                "captured_at": int(time.time() * 1000),
            },
            input_controller=self.input,
            identity_provider=lambda: dict(identity),
            receipt_signer=lambda payload: {
                **identity,
                "signature": hashlib.sha256(b"mqtt-test-key" + payload).hexdigest(),
            },
        )
        self.client = {
            "client_route_id": "client-route-a",
            "identity_fingerprint": "a" * 64,
            "signal_name": "galaxyssi:phone-a",
            "display_name": "Phone A",
            "platform": "android",
            "access": grant_for_executor(True),
        }
        self.published: list[dict] = []
        self.publish_durability: list[bool | None] = []

        def capture_publish(_mqtt, _wire, payload, *, durable=None):
            self.published.append(dict(payload))
            self.publish_durability.append(durable)
            return True

        self.patches = [
            patch.object(desktop_control, "desktop_control_manager", return_value=self.manager),
            patch.object(mqtt_bridge, "desktop_id", return_value="desktop-test"),
            patch.object(mqtt_bridge, "desktop_name", return_value="Test Desktop"),
            patch.object(
                mqtt_bridge,
                "get_signal_bundle",
                return_value={"identityKeySha256": signature_key_id},
            ),
            patch.object(mqtt_bridge.threading, "Thread", ImmediateThread),
            patch.object(
                mqtt_bridge,
                "_publish_phone_payload",
                side_effect=capture_publish,
            ),
        ]
        for item in self.patches:
            item.start()

    def tearDown(self) -> None:
        for item in reversed(self.patches):
            item.stop()
        self.temporary.cleanup()

    def authorize(self) -> dict:
        self.manager.update_settings(enabled=True)
        offer = self.manager.create_offer("pair-token")
        return self.manager.accept_pairing_offer(
            offer["token"],
            "pair-token",
            self.client,
        )

    @staticmethod
    def envelope(target: str = "desktop-test") -> dict:
        return {
            "source_id": "galaxyssi:phone-a",
            "target_id": target,
            "message_id": str(uuid.uuid4()),
        }

    @staticmethod
    def request(authorization: dict) -> dict:
        now = int(time.time() * 1000)
        return {
            "type": mqtt_bridge.DESKTOP_EXECUTOR_REQUEST_TYPE,
            "task_id": str(uuid.uuid4()),
            "action_id": str(uuid.uuid4()),
            "authorization_id": authorization["authorization_id"],
            "desktop_session_id": authorization["desktop_session_id"],
            "tool_id": desktop_control.CLICK_XY,
            "input": {"x": 100, "y": 200, "button": "left"},
            "sent_at": now,
            "expires_at": now + 30_000,
        }

    def test_authorized_control_request_executes_and_returns_receipt(self) -> None:
        authorization = self.authorize()
        handled = mqtt_bridge._route_desktop_control_payload(
            object(),
            self.client,
            self.envelope(),
            self.request(authorization),
            "control",
        )

        self.assertTrue(handled)
        self.assertEqual([("click", 100, 200, "left")], self.input.calls)
        self.assertEqual(
            [mqtt_bridge.DESKTOP_EXECUTOR_EVENT_TYPE, mqtt_bridge.DESKTOP_ACTION_RECEIPT_TYPE],
            [item["type"] for item in self.published],
        )
        self.assertEqual("succeeded", self.published[-1]["status"])
        self.assertEqual(4, self.published[-1]["receipt_version"])
        self.assertTrue(self.published[-1]["signature"])

    def test_low_rate_screen_frame_is_non_durable_and_omits_running_event(self) -> None:
        authorization = self.authorize()
        request = self.request(authorization)
        request.update({
            "tool_id": desktop_control.SCREENSHOT,
            "input": {"stream_frame": True, "stream_fps": 2},
        })

        handled = mqtt_bridge._route_desktop_control_payload(
            object(),
            self.client,
            self.envelope(),
            request,
            "control",
        )

        self.assertTrue(handled)
        self.assertEqual([mqtt_bridge.DESKTOP_ACTION_RECEIPT_TYPE], [
            item["type"] for item in self.published
        ])
        self.assertEqual([False], self.publish_durability)
        self.assertTrue(self.published[0]["output"]["stream_frame"])
        self.assertEqual(2, self.published[0]["output"]["stream_fps"])

    def test_unapproved_phone_receives_failure_without_execution(self) -> None:
        self.manager.update_settings(enabled=True)
        unknown = {
            "authorization_id": str(uuid.uuid4()),
            "desktop_session_id": str(uuid.uuid4()),
        }
        mqtt_bridge._route_desktop_control_payload(
            object(),
            self.client,
            self.envelope(),
            self.request(unknown),
            "control",
        )

        self.assertEqual([], self.input.calls)
        self.assertEqual(1, len(self.published))
        self.assertEqual("authorization_not_found", self.published[0]["error"]["code"])
        self.assertTrue(self.published[0]["signature"])

    def test_restricted_pairing_is_rejected_before_authorization_lookup(self) -> None:
        authorization = self.authorize()
        restricted_client = {
            **self.client,
            "access": grant_for_executor(False),
        }

        mqtt_bridge._route_desktop_control_payload(
            object(),
            restricted_client,
            self.envelope(),
            self.request(authorization),
            "control",
        )

        self.assertEqual([], self.input.calls)
        self.assertEqual("desktop_executor_scope_required", self.published[0]["error"]["code"])
        self.assertTrue(self.published[0]["signature"])

    def test_non_control_channel_and_wrong_target_are_not_executed(self) -> None:
        authorization = self.authorize()
        request = self.request(authorization)
        self.assertTrue(mqtt_bridge._route_desktop_control_payload(
            object(), self.client, self.envelope(), request, "up"
        ))
        self.assertTrue(mqtt_bridge._route_desktop_control_payload(
            object(), self.client, self.envelope("another-desktop"), request, "control"
        ))
        self.assertEqual([], self.input.calls)
        self.assertEqual([], self.published)

    def test_authorized_app_status_is_isolated_to_the_requesting_phone(self) -> None:
        first = self.authorize()
        second_client = {
            **self.client,
            "client_route_id": "client-route-b",
            "identity_fingerprint": "b" * 64,
            "signal_name": "galaxyssi:phone-b",
            "display_name": "Phone B",
            "access": grant_for_executor(True, issued_at_millis=2),
        }
        offer = self.manager.create_offer("pair-token-b")
        second = self.manager.accept_pairing_offer(
            offer["token"],
            "pair-token-b",
            second_client,
        )

        first_payload = mqtt_bridge._desktop_control_status_payload(
            self.client,
            "requested_by_phone",
        )
        second_payload = mqtt_bridge._desktop_control_status_payload(
            second_client,
            "requested_by_phone",
        )

        self.assertEqual(
            [first["authorization_id"]],
            [row["authorization_id"] for row in first_payload["items"]],
        )
        self.assertEqual(
            [second["authorization_id"]],
            [row["authorization_id"] for row in second_payload["items"]],
        )
        self.assertEqual(
            "galaxyssi.authorized-app/1.0",
            first_payload["authorized_app_contract"],
        )

    def test_phone_can_view_its_revoked_record_without_receiving_an_active_handle(self) -> None:
        authorization = self.authorize()
        self.manager.revoke_by_client(
            authorization["authorization_id"],
            self.client,
        )

        payload = mqtt_bridge._desktop_control_status_payload(
            self.client,
            "requested_by_phone",
        )

        self.assertEqual(1, len(payload["items"]))
        self.assertEqual("revoked", payload["items"][0]["status"])
        self.assertIsNone(payload["current_authorization"])
        self.assertEqual("", payload["items"][0]["desktop_session_id"])


if __name__ == "__main__":
    unittest.main()
