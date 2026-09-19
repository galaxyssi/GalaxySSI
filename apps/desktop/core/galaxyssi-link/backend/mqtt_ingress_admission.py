"""Authenticate before deduplication; never acknowledge uncommitted wire data."""
import hashlib
import json

from link_protocol import open_wire_packet


TRANSPORT_TYPES = frozenset({"link_resume", "link_resume_ack", "link_rx_stored"})


def failure_key(paired, digest):
    return (str(paired.get("client_route_id") or ""),
            hashlib.sha256(str(paired.get("link_secret") or "").encode()).digest(), digest)


def classify(payload, paired, ciphertext_digest, backoff):
    """Return lane/key/deferred. The handler still rechecks current authorization.

    Only outer-authenticated transport controls bypass the Signal lane. Business
    envelopes never overtake another Signal envelope, including task controls.
    """
    wire = json.loads(open_wire_packet(payload, str(paired.get("link_secret") or "")).decode("utf-8"))
    if not isinstance(wire, dict):
        raise ValueError("Invalid MQTT envelope")
    if wire.get("type") in TRANSPORT_TYPES and wire.get("scheme") != "signal":
        return "transport", hashlib.sha256(payload).digest(), False
    if wire.get("scheme") != "signal":
        return "signal", hashlib.sha256(payload).digest(), False
    if (wire.get("from") != paired.get("signal_name") or
            wire.get("to") != "desktop_" + str(paired.get("local_identity_fingerprint") or "")[:16]):
        raise ValueError("Signal endpoints do not match relationship")
    digest = ciphertext_digest(wire)
    key = failure_key(paired, digest)
    return "signal", key, backoff.defer(key)
