"""Request/response observations have a caller-owned retry, not a second outbox."""

QUERY_RESPONSES = frozenset({
    "agent_task_recovery_result", "agent_task_result_page", "agent_task_result_receipt_confirmed",
})


def needs_durable_outbox(payload_type):
    return payload_type != "delivery_ack" and payload_type not in QUERY_RESPONSES
