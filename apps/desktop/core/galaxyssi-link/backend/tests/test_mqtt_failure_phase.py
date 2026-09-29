import errno
import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch

import mqtt_bridge as bridge
from tests.test_mqtt_durable_delivery import paired_client


class MqttFailurePhaseTest(unittest.TestCase):
    def assert_failure(self, client, exception, target, expected_phase, **patches):
        from contextlib import ExitStack
        message = SimpleNamespace(payload=b"private-payload", topic="private-topic")
        with ExitStack() as stack:
            for name, value in patches.items():
                stack.enter_context(patch.object(bridge, name, return_value=value))
            stack.enter_context(patch.object(bridge, target, side_effect=exception))
            logger = stack.enter_context(patch.object(bridge.log, "error"))
            self.assertIs(False, bridge._process_message(client, None, message))
            logger.assert_called_once()
            template, *args = logger.call_args.args
            text = template % tuple(args)
            self.assertIn("phase=" + expected_phase, text)
            self.assertNotIn("private", text)
            return text

    def test_route_lookup_reports_numeric_os_error_without_path_or_payload(self):
        error = OSError(errno.ENOSPC, "private-message", "private-file")
        text = self.assert_failure(None, error, "_resolve_inbound_topic", "route_lookup")
        self.assertIn("errno=28", text)
        self.assertIn("OSError:unspecified", text)

    def test_generic_error_keeps_stage_without_stringifying_exception(self):
        text = self.assert_failure(None, RuntimeError("private-secret"),
                                   "_resolve_inbound_topic", "route_lookup")
        self.assertIn("errno=None winerror=None", text)

    def test_receipt_failure_is_distinct_from_peer_control(self):
        peer = paired_client("private-route")
        for method, phase in [("handle_verified", "peer_control"),
                              ("accept_delivery_receipt", "delivery_receipt")]:
            with self.subTest(phase=phase):
                client = Mock(spec=bridge.MqttPoolClient)
                client.peer_routes = Mock()
                client.peer_routes.handle_verified.return_value = False
                getattr(client.peer_routes, method).side_effect = OSError(
                    errno.EACCES, "private-error", "private-file")
                with patch.object(bridge, "_resolve_inbound_topic", return_value=("mailbox", peer)), \
                     patch.object(bridge, "open_wire_packet", return_value=b'{}'), \
                     patch.object(bridge.log, "error") as logger:
                    self.assertIs(False, bridge._process_message(client, None,
                        SimpleNamespace(payload=b"private", topic="private")))
                template, *args = logger.call_args.args
                text = template % tuple(args)
                self.assertIn("phase=" + phase, text)
                self.assertIn("errno=13", text)
                self.assertNotIn("private", text)

    def test_non_numeric_os_error_metadata_is_not_logged(self):
        error = OSError("private")
        error.errno = "private-path"
        error.winerror = "private-path"
        text = self.assert_failure(None, error, "_resolve_inbound_topic", "route_lookup")
        self.assertIn("errno=None winerror=None", text)

    def test_stored_inbox_failure_preserves_retry_signal_and_identifies_dispatch(self):
        message = bridge._StoredInboxMessage("private-route", "private-message", 123, "private-token")
        with patch.object(bridge, "_process_stored_message", side_effect=OSError(errno.EIO, "private")), \
             patch.object(bridge.log, "error") as logger:
            self.assertIs(False, bridge._process_message(None, None, message))
        template, *args = logger.call_args.args
        text = template % tuple(args)
        self.assertIn("phase=stored_dispatch", text)
        self.assertIn("errno=5", text)
        self.assertNotIn("private", text)
