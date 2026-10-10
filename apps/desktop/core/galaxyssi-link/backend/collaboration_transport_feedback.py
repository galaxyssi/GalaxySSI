"""Content-free observations for diagnosing a failed collaboration exchange."""
from collections import Counter
from dataclasses import dataclass
import json


REASONS = frozenset({
    "accepted", "unknown", "local_only_payload", "missing_recipient", "recipient_not_authorized",
    "encoded_packet_too_large", "publication_unclassified", "no_admitted_path",
    "attempt_reservation_rejected", "physical_publish_rejected", "broker_ack_failed",
    "attempt_invalid_attempt", "attempt_path_unavailable", "attempt_path_packet_limit",
    "attempt_duplicate_attempt", "attempt_tracking_limit", "attempt_message_content_conflict",
    "attempt_inflight_packet_limit", "attempt_inflight_byte_limit", "attempt_peer_byte_limit",
})
ROUTE_STATES = frozenset({
    "not_observed", "ready", "missing_binding", "inactive_binding", "missing_local_advertisement",
    "expired_local_advertisement", "unconfirmed_local_epoch", "no_local_receive_path",
    "changed_broker_generation", "no_verified_common_route",
})


@dataclass(frozen=True)
class PublishObservation:
    accepted: bool
    reason_code: str = "unknown"
    route_state_after_attempt: str = "not_observed"
    mqtt_connected_after_attempt: bool | None = None

    def __bool__(self):
        return self.accepted is True

    def public(self):
        return {
            "accepted": bool(self),
            "reason_code": self.reason_code if isinstance(self.reason_code, str) and self.reason_code in REASONS else "unknown",
            "route_state_after_attempt": (self.route_state_after_attempt
                if isinstance(self.route_state_after_attempt, str) and self.route_state_after_attempt in ROUTE_STATES else "not_observed"),
            "mqtt_connected_after_attempt": (self.mqtt_connected_after_attempt
                if type(self.mqtt_connected_after_attempt) is bool else None),
        }


class ExchangeObservations:
    def __init__(self):
        self.reasons = Counter()
        self.latest = None

    def record(self, result):
        observation = result if isinstance(result, PublishObservation) else PublishObservation(bool(result))
        self.latest = observation.public()
        self.reasons[self.latest["reason_code"]] += 1
        return bool(observation)

    def details(self, phase, attempts, accepted, *, response_rejections=None):
        return {
            "format": "galaxyssi.collaboration-transport-observation/1",
            "phase": phase,
            "publish_attempts": attempts,
            "accepted_publish_attempts": accepted,
            "reason_counts": dict(sorted(self.reasons.items())),
            "latest_transport_observation": self.latest,
            "authenticated_response_received": False,
            "response_validation_counts": dict(sorted((response_rejections or {}).items())),
            "response_observation_scope": "active_request_authenticated_peer_only",
            "remote_execution_state": "unknown",
            "interpretation": "local_observations_not_root_cause_or_remote_failure",
        }


class PublicationRejected(ConnectionError):
    def __init__(self, observation, *, guidance=None):
        if not isinstance(observation, dict):
            raise TypeError("Transport observation must be a structured object")
        self.observation = observation
        self.explanation = (
            "Collaboration transport rejected all publish attempts; phone connectivity is unconfirmed. "
            "Retry this exchange after transport recovery; do not restart completed work "
            "or infer that the phone is powered off."
        )
        if guidance is not None:
            self.explanation += " " + guidance
        super().__init__(self.explanation + " " + json.dumps(observation, separators=(",", ":")))


class ResponseUnconfirmed(TimeoutError):
    def __init__(self, observation, *, guidance=None):
        if not isinstance(observation, dict):
            raise TypeError("Transport observation must be a structured object")
        self.observation = observation
        self.explanation = (
            "Collaboration exchange timed out without a valid scope-matched response; publishing is not proof of delivery. "
            "Preserve saved work and retry the exchange without repeating completed work."
        )
        if guidance is not None:
            self.explanation += " " + guidance
        super().__init__(self.explanation + " " + json.dumps(observation, separators=(",", ":")))


def model_failure_result(error):
    if not isinstance(error, (PublicationRejected, ResponseUnconfirmed)):
        return None
    payload = {"success": False, "status": "transport_unconfirmed", "error": error.explanation,
               "transport_observation": error.observation}
    return {"success": False, "contentItems": [{"type": "inputText", "text": json.dumps(payload)}]}
