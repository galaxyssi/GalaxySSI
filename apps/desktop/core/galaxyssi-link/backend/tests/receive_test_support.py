"""Persist the same authenticated-body contract returned by the Signal sidecar."""
import hashlib
import json

from signal_receive_handoff import persist_receive


def store_received_envelope(route, envelope):
    plaintext = json.dumps(envelope, ensure_ascii=False)
    digest = hashlib.sha256(plaintext.encode()).hexdigest()
    persist_receive(route, envelope["source_id"], 1, {
        "plaintext": plaintext, "receiveDigest": digest, "contentHash": digest,
    })
    return envelope


def complete_received_envelope(route, envelope):
    import signal_receive_dispatch as dispatch
    store_received_envelope(route, envelope)
    with dispatch.DispatchGuard(route, envelope["message_id"]) as guard:
        dispatch.finish(guard, dispatch.begin(guard, envelope))
    return envelope
