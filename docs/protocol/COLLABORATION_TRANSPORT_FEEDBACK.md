# Collaboration Transport Feedback

Desktop read and interim-publication tools share an authenticated request/response
exchange with the originating App. Failure to obtain a response is not evidence
that a member failed, a model stopped, or the phone is powered off.

## Observations Returned to the Agent

The existing failed dynamic-tool result remains `success: false`. For typed
transport failures its complete `inputText` is a JSON object with
`status: transport_unconfirmed`, a short error explanation, and
`transport_observation` in format `galaxyssi.collaboration-transport-observation/1`.
These observations do not include selectors, evidence text, mailbox topics,
credentials, or another member's data.

The observation contains:

- `phase`: the actual read, confirmation, publication, listing, or status phase.
- `publish_attempts` and `accepted_publish_attempts`: local admission only, never
  proof of peer delivery or successful business execution.
- `reason_counts`: bounded local reason codes, such as unclassified publication,
  oversized packet, no admitted path, reservation rejection, physical publication
  rejection, and failed broker acknowledgement.
- `latest_transport_observation`: admission reason plus the local route state
  and aggregate MQTT connectivity observed after that attempt.
- `authenticated_response_received: false` and `remote_execution_state: unknown`.

A post-attempt route observation may already differ from the state at rejection.
It must not overwrite the publication's reason or be reported as its proven cause.
In particular, `mqtt_connected_after_attempt: true` does not imply a verified
pair route or a reachable application. `ready` does not prove a reply was received.

The existing generic 500-character exception preview remains for other failures.
Only these typed, content-free failures receive the complete structured result,
so JSON and essential diagnostic fields cannot be cut off before reaching the
Agent. Original-evidence confirmation still must succeed before the tool returns
an original page as confirmed delivery.

The milestone wrapper preserves the typed observation object through the Codex
dynamic-tool response and adds guidance for the actual mode. An uncertain
`publish` keeps the same milestone ID and artifact on retry. Failed `list` or
`status` reads explicitly report that they submitted no artifact; neither read
is evidence that an earlier publication failed. They must not acquire publication
authority from a transport failure. The observation constructors reject plain
strings instead of silently losing structured failure facts.

## Local Operational Diagnostics

`/health` and `/api/link/transport-diagnostics` expose aggregate
`peers.admission_states` alongside the existing configured/ready counts. They
distinguish missing/inactive bindings, absent/expired advertisements, unconfirmed
local epochs, unavailable receive paths, changed generations, and the absence of
a verified common route. These aggregates contain no peer identities.

This increment changes diagnostic feedback, not authorization or retry policy.
It does not add a durable queue for ephemeral reads, enlarge time budgets,
accept unauthenticated replies, restart model tasks, or reinterpret an unknown
remote outcome as success. A successful unit test of fault reporting is not a
successful live collaboration or proof that an Agent selected a better strategy.
