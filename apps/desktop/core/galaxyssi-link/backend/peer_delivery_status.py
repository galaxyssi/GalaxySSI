"""Repair interrupted delivery-status projection, never resend user content."""
from link_delivery import outbound_statuses


def reconcile(store, messages):
    pending = [(item["client_route_id"], item["message_id"]) for item in messages
               if item.get("direction") == "outbound"
               and item.get("delivery_status") in {"sending", "queued", "sent"}]
    if not pending:
        return messages
    states = outbound_statuses(pending)
    result = []
    for item in messages:
        route, message = item["client_route_id"], item["message_id"]
        if states.get((route, message)) == "failed":
            item = store.mark_outbound_failed(route, message) or item
        result.append(item)
    return result
