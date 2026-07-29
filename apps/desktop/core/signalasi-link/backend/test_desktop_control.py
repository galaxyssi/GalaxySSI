import base64
import hashlib
import tempfile
import threading
import unittest
import uuid
from pathlib import Path

from pairing_access import grant_for_executor
from desktop_control import (
    CLICK_XY,
    DEFAULT_ALLOWED_TOOLS,
    FILE_SELECT,
    SCREENSHOT,
    TYPE_TEXT,
    WINDOW_SWITCH,
    RECEIPT_SIGNED_FIELDS,
    DesktopControlError,
    DesktopControlManager,
    WindowsInputController,
    _canonical_json,
)
from tool_handle_registry import ToolHandleRegistry, ToolHandleScope


class FakeClock:
    def __init__(self, value: float = 1_800_000_000.0):
        self.value = value

    def __call__(self) -> float:
        return self.value


class FakeInput:
    def __init__(self):
        self.calls = []
        self.locked = False

    def is_locked(self):
        return self.locked

    def click(self, x, y, button, *, source_width=None, source_height=None):
        self.calls.append(("click", x, y, button))
        self.coordinate_space = (source_width, source_height)

    def type_text(self, text):
        self.calls.append(("type", text))

    def hotkey(self, keys):
        self.calls.append(("hotkey", list(keys)))

    def scroll(self, delta):
        self.calls.append(("scroll", delta))

    def window_switch(self, direction):
        self.calls.append(("window_switch", direction))

    def select_file(self, path):
        self.calls.append(("file_select", path))


class FakeReceiptIdentity:
    signer_id = "desktop_test"
    signature_key_id = hashlib.sha256(b"desktop-test-public-key").hexdigest()
    secret = b"desktop-test-signing-key"

    def identity(self):
        return {
            "signer_id": self.signer_id,
            "signature_key_id": self.signature_key_id,
        }

    def sign(self, payload):
        return {
            **self.identity(),
            "signature": hashlib.sha256(self.secret + payload).hexdigest(),
        }

    def verify(self, receipt):
        payload = _canonical_json({
            key: receipt[key]
            for key in RECEIPT_SIGNED_FIELDS
        })
        return receipt.get("signature") == hashlib.sha256(self.secret + payload).hexdigest()


class DesktopControlTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.clock = FakeClock()
        self.input = FakeInput()
        self.identity = FakeReceiptIdentity()
        self.handles = ToolHandleRegistry(now=self.clock)
        self.screenshot_calls = 0

        def screenshot():
            self.screenshot_calls += 1
            return {
                "image_mime": "image/jpeg",
                "image_base64": "/9j/2Q==",
                "width": 960,
                "height": 540,
                "original_width": 1920,
                "original_height": 1080,
                "bytes": 4,
                "captured_at": int(self.clock() * 1000),
            }

        self.manager = DesktopControlManager(
            Path(self.temporary.name) / "control.json",
            now=self.clock,
            screenshot_provider=screenshot,
            input_controller=self.input,
            identity_provider=self.identity.identity,
            receipt_signer=self.identity.sign,
            handle_registry=self.handles,
        )
        self.client = {
            "client_route_id": "client-route-1",
            "identity_fingerprint": "a" * 64,
            "signal_name": "signalasi:" + "a" * 16,
            "display_name": "Test Phone",
            "platform": "android",
            "access": grant_for_executor(
                True,
                issued_at_millis=int(self.clock() * 1_000),
            ),
        }

    def tearDown(self):
        self.temporary.cleanup()

    def authorize(self):
        self.manager.update_settings(enabled=True)
        offer = self.manager.create_offer("pair-token")
        self.assertIsNotNone(offer)
        authorization = self.manager.accept_pairing_offer(
            offer["token"],
            "pair-token",
            self.client,
        )
        self.assertEqual("active", authorization["status"])
        return authorization

    def request(self, authorization, tool=SCREENSHOT, input_value=None, action_id=None):
        now = int(self.clock() * 1000)
        return {
            "type": "desktop_executor_request",
            "task_id": "task-1",
            "action_id": action_id or str(uuid.uuid4()),
            "authorization_id": authorization["authorization_id"],
            "desktop_session_id": authorization["desktop_session_id"],
            "tool_id": tool,
            "input": input_value or {},
            "sent_at": now,
            "expires_at": now + 30_000,
        }

    def test_offer_requires_enabled_executor_and_is_single_use(self):
        self.assertIsNone(self.manager.create_offer("pair-token"))
        authorization = self.authorize()
        self.assertEqual("active", authorization["status"])
        consumed_offer = self.manager.create_offer("second-pair-token")
        self.assertIsNotNone(consumed_offer)
        pending = self.manager.accept_pairing_offer(
            consumed_offer["token"],
            "second-pair-token",
            {**self.client, "client_route_id": "client-route-2", "identity_fingerprint": "b" * 64},
        )
        self.assertEqual("active", pending["status"])
        with self.assertRaises(DesktopControlError) as raised:
            self.manager.accept_pairing_offer(
                consumed_offer["token"],
                "second-pair-token",
                {**self.client, "client_route_id": "client-route-2", "identity_fingerprint": "b" * 64},
            )
        self.assertEqual("authorization_offer_invalid", raised.exception.code)

    def test_pairing_qr_approves_executor_access_in_the_same_consent_step(self):
        self.manager.update_settings(enabled=True)
        offer = self.manager.create_offer("pair-token")

        authorization = self.manager.accept_pairing_offer(
            offer["token"],
            "pair-token",
            self.client,
        )

        self.assertEqual("active", authorization["status"])
        self.assertGreater(authorization["granted_at"], 0)
        self.assertEqual("pairing_qr", authorization["grant_source"])
        self.assertEqual("desktop_executor", authorization["access_profile"])
        self.assertEqual(64, len(authorization["pairing_access_sha256"]))
        self.assertEqual("signalasi:" + "a" * 16, authorization["app_instance_id"])
        self.assertEqual("Test Phone", authorization["app_name"])
        self.assertEqual("a" * 64, authorization["app_identity_fingerprint"])
        self.assertEqual("android", authorization["app_platform"])
        self.assertIn("desktop.control", authorization["access_scopes"])
        self.assertEqual(
            "signalasi.authorized-app/1.0",
            self.manager.status()["authorized_app_contract"],
        )

    def test_repairing_refreshes_the_authorized_standard_tool_set(self):
        authorization = self.authorize()
        authorization_id = authorization["authorization_id"]
        self.manager._state["authorizations"][authorization_id]["allowed_tools"] = [
            SCREENSHOT
        ]
        offer = self.manager.create_offer("renewed-pair-token")

        rebound = self.manager.accept_pairing_offer(
            offer["token"],
            "renewed-pair-token",
            self.client,
        )

        self.assertEqual(authorization_id, rebound["authorization_id"])
        self.assertEqual(list(DEFAULT_ALLOWED_TOOLS), rebound["allowed_tools"])

    def test_restricted_pairing_cannot_be_promoted_by_the_control_offer(self):
        self.manager.update_settings(enabled=True)
        offer = self.manager.create_offer("pair-token")
        restricted = {
            **self.client,
            "access": grant_for_executor(
                False,
                issued_at_millis=int(self.clock() * 1_000),
            ),
        }

        with self.assertRaises(DesktopControlError) as raised:
            self.manager.accept_pairing_offer(
                offer["token"],
                "pair-token",
                restricted,
            )

        self.assertEqual("desktop_executor_scope_required", raised.exception.code)
        self.assertEqual([], self.manager.status()["authorizations"])

    def test_offer_is_rejected_if_executor_is_disabled_before_pairing_completes(self):
        self.manager.update_settings(enabled=True)
        offer = self.manager.create_offer("pair-token")
        self.manager.update_settings(enabled=False)
        with self.assertRaises(DesktopControlError) as raised:
            self.manager.accept_pairing_offer(offer["token"], "pair-token", self.client)
        self.assertEqual("desktop_executor_disabled", raised.exception.code)

    def test_authorized_screenshot_emits_running_and_replays_without_recapture(self):
        authorization = self.authorize()
        action_id = str(uuid.uuid4())
        events = []
        request = self.request(authorization, action_id=action_id)
        result = self.manager.execute_request(request, self.client, on_running=events.append)
        self.assertEqual("succeeded", result["status"])
        self.assertEqual(SCREENSHOT, result["tool_id"])
        self.assertEqual(4, result["receipt_version"])
        self.assertEqual(
            authorization["desktop_session_id"],
            result["desktop_session_id"],
        )
        self.assertTrue(self.identity.verify(result))
        self.assertEqual("signalasi:" + "a" * 16, result["controller_app_instance_id"])
        self.assertEqual("Test Phone", result["controller_name"])
        self.assertEqual("android", result["controller_platform"])
        self.assertEqual("a" * 64, result["controller_fingerprint"])
        self.assertEqual(
            hashlib.sha256(b"\xff\xd8\xff\xd9").hexdigest(),
            result["evidence_sha256"],
        )
        self.assertEqual(1, len(events))
        self.assertEqual(1, self.screenshot_calls)
        replay = self.manager.execute_request(request, self.client)
        self.assertTrue(replay["replayed"])
        self.assertTrue(self.identity.verify(replay))
        self.assertEqual(1, self.screenshot_calls)
        state_text = (Path(self.temporary.name) / "control.json").read_text(encoding="utf-8")
        self.assertNotIn("/9j/2Q==", state_text)

    def test_duplicate_action_with_different_input_is_rejected(self):
        authorization = self.authorize()
        action_id = str(uuid.uuid4())
        first = self.request(
            authorization,
            CLICK_XY,
            {"x": 100, "y": 200, "button": "left"},
            action_id,
        )
        self.assertEqual("succeeded", self.manager.execute_request(first, self.client)["status"])
        conflicting = self.request(
            authorization,
            CLICK_XY,
            {"x": 101, "y": 200, "button": "left"},
            action_id,
        )
        with self.assertRaises(DesktopControlError) as raised:
            self.manager.execute_request(conflicting, self.client)
        self.assertEqual("duplicate_action_conflict", raised.exception.code)

    def test_click_and_text_are_executed_but_text_is_redacted_from_audit(self):
        authorization = self.authorize()
        click = self.manager.execute_request(
            self.request(authorization, CLICK_XY, {"x": 100, "y": 200, "button": "left"}),
            self.client,
        )
        self.assertEqual("succeeded", click["status"])
        secret = "private text must not enter the audit log"
        typed = self.manager.execute_request(
            self.request(authorization, TYPE_TEXT, {"text": secret}),
            self.client,
        )
        self.assertEqual("succeeded", typed["status"])
        state_text = (Path(self.temporary.name) / "control.json").read_text(encoding="utf-8")
        self.assertNotIn(secret, state_text)
        self.assertIn("typed 41 chars", state_text)

    def test_window_switch_and_file_select_use_standard_tools(self):
        authorization = self.authorize()
        selected = Path(self.temporary.name) / "private project.txt"
        selected.write_text("private", encoding="utf-8")

        next_window = self.manager.execute_request(
            self.request(
                authorization,
                WINDOW_SWITCH,
                {"direction": "next"},
            ),
            self.client,
        )
        previous_window = self.manager.execute_request(
            self.request(
                authorization,
                WINDOW_SWITCH,
                {"direction": "previous"},
            ),
            self.client,
        )
        file_selection = self.manager.execute_request(
            self.request(
                authorization,
                FILE_SELECT,
                {"path": str(selected)},
            ),
            self.client,
        )

        self.assertEqual("succeeded", next_window["status"])
        self.assertEqual("succeeded", previous_window["status"])
        self.assertEqual("succeeded", file_selection["status"])
        self.assertEqual(
            [
                ("window_switch", "next"),
                ("window_switch", "previous"),
                ("file_select", str(selected.resolve())),
            ],
            self.input.calls,
        )
        self.assertEqual("private project.txt", file_selection["output"]["file_name"])
        state_text = (Path(self.temporary.name) / "control.json").read_text(
            encoding="utf-8"
        )
        self.assertNotIn(str(selected), state_text)
        self.assertIn("selected an existing file in the active file dialog", state_text)

    def test_file_select_rejects_missing_files_without_input(self):
        authorization = self.authorize()
        missing = Path(self.temporary.name) / "missing.txt"

        receipt = self.manager.execute_request(
            self.request(
                authorization,
                FILE_SELECT,
                {"path": str(missing)},
            ),
            self.client,
        )

        self.assertEqual("failed", receipt["status"])
        self.assertEqual("file_not_found", receipt["error_code"])
        self.assertEqual([], self.input.calls)
        self.assertNotIn(str(missing), str(receipt))

    def test_click_coordinate_space_is_forwarded_and_scaled_for_windows_dpi(self):
        authorization = self.authorize()
        click = self.manager.execute_request(
            self.request(
                authorization,
                CLICK_XY,
                {
                    "x": 3000,
                    "y": 1800,
                    "button": "left",
                    "coordinate_width": 3840,
                    "coordinate_height": 2160,
                },
            ),
            self.client,
        )
        self.assertEqual("succeeded", click["status"])
        self.assertEqual((3840, 2160), self.input.coordinate_space)
        self.assertEqual(
            (1200, 719),
            WindowsInputController.scale_point(
                3000,
                1800,
                source_width=3840,
                source_height=2160,
                target_width=1536,
                target_height=864,
            ),
        )

    def test_identity_mismatch_expiry_disable_and_revoke_are_rejected(self):
        authorization = self.authorize()
        request = self.request(authorization)
        mismatched = {**self.client, "identity_fingerprint": "b" * 64}
        with self.assertRaises(DesktopControlError) as mismatch:
            self.manager.execute_request(request, mismatched)
        self.assertEqual("authorization_identity_mismatch", mismatch.exception.code)

        expired = self.request(authorization)
        self.clock.value += 31
        with self.assertRaises(DesktopControlError) as expiry:
            self.manager.execute_request(expired, self.client)
        self.assertEqual("message_expired", expiry.exception.code)

        self.manager.update_settings(enabled=False)
        with self.assertRaises(DesktopControlError) as disabled:
            self.manager.execute_request(self.request(authorization), self.client)
        self.assertEqual("desktop_executor_disabled", disabled.exception.code)

        self.manager.update_settings(enabled=True)
        self.manager.revoke_by_client(authorization["authorization_id"], self.client)
        with self.assertRaises(DesktopControlError) as revoked:
            self.manager.execute_request(self.request(authorization), self.client)
        self.assertEqual("authorization_not_found", revoked.exception.code)

    def test_execution_rejects_downgraded_or_replaced_pairing_grants(self):
        authorization = self.authorize()
        restricted = {
            **self.client,
            "access": grant_for_executor(
                False,
                issued_at_millis=int(self.clock() * 1_000),
            ),
        }
        with self.assertRaises(DesktopControlError) as downgraded:
            self.manager.execute_request(self.request(authorization), restricted)
        self.assertEqual("desktop_executor_scope_required", downgraded.exception.code)

        replaced_grant = {
            **self.client,
            "access": grant_for_executor(
                True,
                issued_at_millis=int(self.clock() * 1_000) + 1,
            ),
        }
        with self.assertRaises(DesktopControlError) as replaced:
            self.manager.execute_request(self.request(authorization), replaced_grant)
        self.assertEqual("pairing_authorization_stale", replaced.exception.code)

    def test_pairing_authorization_survives_restart_without_another_approval(self):
        authorization = self.authorize()
        reloaded_handles = ToolHandleRegistry(now=self.clock)
        reloaded = DesktopControlManager(
            Path(self.temporary.name) / "control.json",
            now=self.clock,
            screenshot_provider=lambda: {
                "image_mime": "image/jpeg",
                "image_base64": "/9j/2Q==",
                "width": 1,
                "height": 1,
                "original_width": 1,
                "original_height": 1,
                "bytes": 4,
                "captured_at": int(self.clock() * 1_000),
            },
            input_controller=self.input,
            identity_provider=self.identity.identity,
            receipt_signer=self.identity.sign,
            handle_registry=reloaded_handles,
        )

        restored = reloaded.status(self.client["client_route_id"])["authorizations"][0]
        self.assertEqual(authorization["authorization_id"], restored["authorization_id"])
        self.assertEqual("active", restored["status"])
        self.assertNotEqual(authorization["desktop_session_id"], restored["desktop_session_id"])
        self.assertEqual(
            "succeeded",
            reloaded.execute_request(
                self.request(restored),
                self.client,
            )["status"],
        )

    def test_explicit_desktop_session_is_required_and_route_scoped(self):
        authorization = self.authorize()
        missing = self.request(authorization)
        missing.pop("desktop_session_id")
        with self.assertRaises(DesktopControlError) as required:
            self.manager.execute_request(missing, self.client)
        self.assertEqual("desktop_session_required", required.exception.code)

        released = self.request(authorization)
        self.assertTrue(
            self.handles.release(
                authorization["desktop_session_id"],
                scope=ToolHandleScope(self.client["client_route_id"]),
            )
        )
        with self.assertRaises(DesktopControlError) as stale:
            self.manager.execute_request(released, self.client)
        self.assertEqual("tool_handle_not_found", stale.exception.code)
        self.assertTrue(stale.exception.retryable)

        refreshed = self.manager.status(
            self.client["client_route_id"]
        )["authorizations"][0]
        wrong_scope = self.handles.create(
            kind="desktop_session",
            resource_id=refreshed["authorization_id"],
            scope=ToolHandleScope("another-client-route"),
            capabilities=[SCREENSHOT],
        )
        crossed = self.request(refreshed)
        crossed["desktop_session_id"] = wrong_scope["handle_id"]
        with self.assertRaises(DesktopControlError) as mismatch:
            self.manager.execute_request(crossed, self.client)
        self.assertEqual("tool_handle_owner_mismatch", mismatch.exception.code)

    def test_revocation_while_waiting_for_input_lock_prevents_execution(self):
        authorization = self.authorize()
        request = self.request(
            authorization,
            CLICK_XY,
            {"x": 10, "y": 20, "button": "left"},
        )
        running = threading.Event()
        completed = []
        self.manager._input_lock.acquire()
        worker = threading.Thread(
            target=lambda: completed.append(
                self.manager.execute_request(
                    request,
                    self.client,
                    on_running=lambda _event: running.set(),
                )
            ),
        )
        worker.start()
        self.assertTrue(running.wait(timeout=2))
        self.manager.revoke_by_client(authorization["authorization_id"], self.client)
        self.manager._input_lock.release()
        worker.join(timeout=2)

        self.assertFalse(worker.is_alive())
        self.assertEqual([], self.input.calls)
        self.assertEqual("failed", completed[0]["status"])
        self.assertEqual("authorization_not_found", completed[0]["error"]["code"])
        self.assertTrue(self.identity.verify(completed[0]))

    def test_signed_receipts_survive_reload_without_screenshot_payloads(self):
        authorization = self.authorize()
        receipt = self.manager.execute_request(self.request(authorization), self.client)
        reloaded = DesktopControlManager(
            Path(self.temporary.name) / "control.json",
            now=self.clock,
            screenshot_provider=lambda: {},
            input_controller=self.input,
            identity_provider=self.identity.identity,
            receipt_signer=self.identity.sign,
            handle_registry=self.handles,
        )

        recent = reloaded.status(self.client["client_route_id"])["recent_receipts"]
        self.assertEqual(1, len(recent))
        self.assertEqual(receipt["receipt_id"], recent[0]["receipt_id"])
        self.assertTrue(self.identity.verify(recent[0]))
        self.assertNotIn("image_base64", recent[0]["output"]["screenshot"])
        self.assertEqual(
            receipt["evidence_sha256"],
            recent[0]["output"]["screenshot"]["image_sha256"],
        )
        self.assertIsNone(recent[0]["post_screenshot"])

    def test_failure_receipt_is_identity_signed_and_request_bound(self):
        authorization = self.authorize()
        request = self.request(authorization, TYPE_TEXT, {"text": "private"})
        receipt = self.manager.failure_receipt(
            request,
            self.client,
            DesktopControlError("desktop_control_busy", "Desktop control capacity is busy", retryable=True),
        )

        self.assertEqual("failed", receipt["status"])
        self.assertEqual("desktop_control_busy", receipt["error_code"])
        self.assertTrue(receipt["error_retryable"])
        self.assertTrue(self.identity.verify(receipt))
        self.assertEqual("Test Phone", receipt["controller_name"])
        self.assertEqual(
            hashlib.sha256(_canonical_json({"text": "private"})).hexdigest(),
            receipt["input_sha256"],
        )

    def test_controller_identity_and_result_are_tamper_evident(self):
        authorization = self.authorize()
        receipt = self.manager.execute_request(
            self.request(authorization),
            self.client,
        )

        for field, value in (
            ("controller_app_instance_id", "signalasi:other"),
            ("controller_name", "Other phone"),
            ("controller_platform", "ios"),
            ("tool_id", TYPE_TEXT),
            ("status", "failed"),
            ("completed_at", receipt["completed_at"] + 1),
        ):
            tampered = dict(receipt)
            tampered[field] = value
            self.assertFalse(self.identity.verify(tampered), field)

    def test_oversized_screenshot_is_rejected_before_transport(self):
        authorization = self.authorize()
        oversized = b"x" * 100_001
        self.manager._screenshot_provider = lambda: {
            "image_mime": "image/jpeg",
            "image_base64": base64.b64encode(oversized).decode("ascii"),
            "width": 960,
            "height": 540,
            "original_width": 1920,
            "original_height": 1080,
            "bytes": len(oversized),
            "captured_at": int(self.clock() * 1_000),
        }

        receipt = self.manager.execute_request(
            self.request(authorization),
            self.client,
        )

        self.assertEqual("failed", receipt["status"])
        self.assertEqual("screenshot_too_large", receipt["error_code"])
        self.assertTrue(self.identity.verify(receipt))
        self.assertNotIn("image_base64", str(receipt))

    def test_screenshot_byte_metadata_must_match_payload(self):
        authorization = self.authorize()
        self.manager._screenshot_provider = lambda: {
            "image_mime": "image/jpeg",
            "image_base64": "/9j/2Q==",
            "width": 1,
            "height": 1,
            "original_width": 1,
            "original_height": 1,
            "bytes": 5,
            "captured_at": int(self.clock() * 1_000),
        }

        receipt = self.manager.execute_request(
            self.request(authorization),
            self.client,
        )

        self.assertEqual("failed", receipt["status"])
        self.assertEqual("invalid_screenshot", receipt["error_code"])
        self.assertTrue(self.identity.verify(receipt))

    def test_request_digest_binds_task_action_and_controller_identity(self):
        authorization = self.authorize()
        original = self.request(authorization)
        first = self.manager.failure_receipt(
            original,
            self.client,
            DesktopControlError("test", "test"),
        )
        second = self.manager.failure_receipt(
            {**original, "task_id": "task-2"},
            self.client,
            DesktopControlError("test", "test"),
        )
        third = self.manager.failure_receipt(
            original,
            {**self.client, "client_route_id": "client-route-2"},
            DesktopControlError("test", "test"),
        )

        self.assertNotEqual(first["request_sha256"], second["request_sha256"])
        self.assertNotEqual(first["request_sha256"], third["request_sha256"])

    def test_route_scoped_status_only_contains_its_own_receipts(self):
        first_authorization = self.authorize()
        self.manager.execute_request(self.request(first_authorization), self.client)
        second_client = {
            **self.client,
            "client_route_id": "client-route-2",
            "identity_fingerprint": "b" * 64,
            "signal_name": "signalasi:" + "b" * 16,
            "display_name": "Second Phone",
        }
        offer = self.manager.create_offer("second-pair-token")
        second_pending = self.manager.accept_pairing_offer(
            offer["token"],
            "second-pair-token",
            second_client,
        )
        self.manager.execute_request(
            self.request(second_pending),
            second_client,
        )

        first_receipts = self.manager.status("client-route-1")["recent_receipts"]
        second_receipts = self.manager.status("client-route-2")["recent_receipts"]
        self.assertEqual(
            [first_authorization["authorization_id"]],
            [receipt["authorization_id"] for receipt in first_receipts],
        )
        self.assertEqual(
            [second_pending["authorization_id"]],
            [receipt["authorization_id"] for receipt in second_receipts],
        )


if __name__ == "__main__":
    unittest.main()
