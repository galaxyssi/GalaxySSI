"""Final responses must not wait for maintenance or lose durable retry ownership."""
from contextlib import ExitStack
from unittest import TestCase
from unittest.mock import Mock, patch

import agent_reply_timing
import agent_task_result_archive
import mqtt_bridge as bridge
from test_agent_task_result_outbox import outcome


class ReplyDeliveryLatencyTest(TestCase):
    def test_final_is_flushed_after_durable_handoff_without_waiting_for_inbox(self):
        for accept, fail_flush in ((True, False), (True, True), (False, False)):
            with self.subTest(accept=accept, fail_flush=fail_flush), ExitStack() as stack:
                order = []
                client = Mock(spec=bridge.MqttPoolClient)
                client.is_connected.return_value = True
                stack.enter_context(patch.object(agent_task_result_archive.archive, "put", return_value=None))
                stack.enter_context(patch.object(bridge, "queue_task_result", side_effect=lambda *a, **k: order.append("durable") or {"scope": "test"}))
                stack.enter_context(patch.object(bridge, "_ensure_outbound_retry_thread"))
                stack.enter_context(patch.object(bridge, "_publish_pending_task_result", side_effect=lambda *a: order.append("handoff") or accept))
                def flush(*args, **kwargs):
                    self.assertEqual("phone", kwargs["preferred_client_route_id"])
                    order.append("flush")
                    if fail_flush:
                        raise RuntimeError("network unavailable")
                stack.enter_context(patch.object(bridge, "flush_outbound_messages", side_effect=flush))
                inbox = stack.enter_context(patch.object(bridge, "flush_pending_inbound_messages"))
                wake = stack.enter_context(patch.object(bridge, "outbound_retry_wake_event"))
                result = bridge._publish_or_queue_task_result(client, {"_client_route_id": "phone"}, outcome())
                self.assertEqual(accept, result)
                self.assertEqual(["durable", "handoff"] + (["flush"] if accept else []), order)
                inbox.assert_not_called()
                self.assertEqual(fail_flush, wake.set.called)

    def test_measurement_failure_never_changes_result_or_operation_exception(self):
        with patch.object(agent_reply_timing, "record_task", side_effect=OSError("telemetry unavailable")):
            self.assertEqual("reply", agent_reply_timing.measure("task", "encrypt", lambda: "reply"))
            error = ValueError("preserve this failure")
            def fail():
                raise error
            with self.assertRaises(ValueError) as caught:
                agent_reply_timing.measure("task", "encrypt", fail)
            self.assertIs(error, caught.exception)

    def test_measurements_have_distinct_operation_ids_and_no_content(self):
        with patch.object(agent_reply_timing, "record_task") as record:
            for _ in range(2):
                agent_reply_timing.measure("task", "encrypt", lambda: "private reply")
        self.assertEqual(4, record.call_count)
        self.assertEqual(record.call_args_list[0].kwargs["operation_id"], record.call_args_list[1].kwargs["operation_id"])
        self.assertNotEqual(record.call_args_list[0].kwargs["operation_id"], record.call_args_list[2].kwargs["operation_id"])
        self.assertNotIn("private reply", str(record.call_args_list))
