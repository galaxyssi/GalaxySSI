"""A terminal receive proof can repeat an ACK, never re-enter business dispatch."""
from link_delivery import bind_ciphertext
from link_protocol import validate_envelope
from mqtt_delivery_envelope import content_hash


def acknowledge_completed(bridge, mqttc, paired, wire, envelope, *, delivery_frame=None, chunk_transfer=None):
    validate_envelope(envelope)
    if envelope["source_id"] != paired["signal_name"] or envelope["target_id"] != bridge.desktop_id():
        raise ValueError("Completed receive endpoints do not match pairing")
    mid, route = envelope["message_id"], paired["client_route_id"]
    if delivery_frame is not None and delivery_frame.message.message_id != mid:
        raise ValueError("Completed receive attempt identity mismatch")
    wire_hash = content_hash(wire)
    bind_ciphertext(route, bridge._signal_ciphertext_digest(wire), mid, receipt_hash=wire_hash)
    payload = dict(envelope["payload"])
    payload.setdefault("source_message_id", mid)
    bridge._ack_stored_application(mqttc, wire, envelope, payload, [], duplicate=True,
        delivery_frame=delivery_frame, chunk_transfer=chunk_transfer, wire_hash=wire_hash)
