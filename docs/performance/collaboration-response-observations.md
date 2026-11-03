# Collaboration response observations

Desktop 1.4.45 adds content-free observations to distinguish a missing reply from
a reply rejected by the existing execution-scope and result validation. It does
not change the exchange deadline, retry cadence, authorization, durable delivery,
task scheduling, or UI. This is diagnosis, not a claim that network latency is fixed.

## Receive path

Authenticated collaboration recall, publication and tool-test responses produce
`Collaboration receive` observations at stored, dispatch, finished or failed
boundaries. Timings use only the Desktop monotonic clock:

- `queue_ms`: packet receipt to handler entry.
- `decrypt_ms`: Signal decrypt/replay boundary, excluding subsequent bookkeeping.
- `handler_elapsed_ms`: handler entry to the reported boundary.

The difference between stored and dispatch observations includes receipt work;
the difference between dispatch and finished includes business handling and its
durable completion. Recovered records without original monotonic stamps report
`-1`, not a fabricated zero. These spans are not phone-to-Desktop network latency,
model runtime, or proof that the receiving Agent understood a result.

## Response admission

The existing broker emits `Collaboration response` with an outcome such as
`accepted`, `no_pending_request`, `deadline_elapsed`, `already_received`, a named
scope-field mismatch, `result_not_object`, `success_not_boolean`,
`result_not_json`, or `response_too_large`. The latter distinguishes a size policy
from a syntax error. A missing pending request alone cannot establish whether a
reply is late, already cleaned up, or unsolicited.

Both observations use the first 16 hex characters of SHA-256(request_id) as `rpc`.
They exclude prompts, result bodies, field values, account identifiers, paths and
raw task/request IDs. This is a correlation token, not an authentication token.
Broker logs run outside its lock and logging failure cannot drop an accepted reply.

While a request is active, rejection counts from its authenticated peer are also
included in `transport_observation.response_validation_counts` in the model-visible
failure result. Another peer cannot populate that request's counts. Empty counts
do not prove that the phone did not process or submit the request. Original
`authenticated_response_received=false` still means no valid scope-matched reply
was accepted; rejected responses do not become accepted evidence.

## Verification boundaries

Unit tests cover exact phase arithmetic on the actual MQTT handler, privacy,
malformed results, all scope-field mismatches, corrected resubmission, duplicate
and late responses, other-peer isolation, diagnostic failure, and preservation
of durable retry after business-handler failure. These isolated tests do not
replace real phone/broker measurements or prove complete research delivery.
