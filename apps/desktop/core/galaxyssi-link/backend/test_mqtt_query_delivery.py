import unittest
from mqtt_query_delivery import needs_durable_outbox


class QueryDeliveryTest(unittest.TestCase):
    def test_observations_do_not_accumulate_after_caller_timeout(self):
        for kind in ("agent_task_recovery_result", "agent_task_result_page", "agent_task_result_receipt_confirmed", "delivery_ack"):
            self.assertFalse(needs_durable_outbox(kind))

    def test_user_results_and_side_effects_remain_durable(self):
        for kind in ("text", "peer_message", "rich_output", "agent_task_event", "artifact_chunk", "desktop_action_receipt", "unknown"):
            self.assertTrue(needs_durable_outbox(kind))
