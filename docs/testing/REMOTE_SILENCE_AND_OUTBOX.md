# Remote silence and bounded MQTT recovery

## Contract

- Broker connectivity is not proof of Desktop task acceptance or task progress.
- Each task has an authenticated response lease. Query attempts are coalesced per source message,
  at most once per 30 seconds. Five minutes of silence and at least three recent unsuccessful
  probes permit terminal recovery. A fresh authenticated task observation renews the lease.
- Each wire query contains exactly one task. Different tasks are never bundled in a status request;
  their query identities, responses and retry accounting remain independent.
- A long process suspension requires fresh probes; historical failures alone cannot trigger fallback.
- A single durable workspace recovery lease performs fallback, independent of visible windows.
- Only conservatively classified, low-risk informational requests may switch providers after
  uncertain delivery. Unknown or potentially mutating work stops local waiting without claiming
  that the remote execution has been cancelled. Existing routing/privacy eligibility still applies.
- If no suitable alternative exists, persist failure and explain why. Do not silently leave a spinner.
- Terminal/superseded sources cannot create new recovery queries.

## Outbox

- A query caller owns retries for status/recovery/result-page requests. Such queries are not also
  queued as new durable MQTT messages. Final-result receipts retain their separate durable intent.
- Active durable outbox capacity is 64 per peer, including 8 reserved control slots. Capacity
  rejection is explicit; user messages are never silently removed to make room.
- Retransmission allows 8 unconfirmed messages per route per 30-second receipt window.
- Legacy unclassified rows older than 15 minutes with no source/dependency/attachment are held,
  retained for inspection and excluded from retries. Holding is not a delivery acknowledgement.
- Desktop coalesces authenticated duplicate ciphertext before Signal processing; transport
  handshakes have a separate lane. Signal messages remain ordered within a peer lane.

## Verification

Run Android unit tests for `AgentRemoteSilencePolicyTest`, `MqttOutboxRetryWindowTest`, and
`AgentProcessClockPolicyTest`. Run device tests for `GalaxySSILinkOutboxDatabaseTest`,
`AgentRemoteSilenceDeviceTest`, and `AgentConnectorFallbackRuntimeDeviceTest`.

Use only an explicitly selected phone serial. Live probes are opt-in:
`MqttOutboxAuditDeviceTest` requires `live_link_audit=true` or `live_link_send=true`;
`AgentDeliveryLiveDeviceTest` requires `live_delivery=true` and the exact model name.
Live tests must not be represented as exhaustive weak-network or multi-day validation.

Check separately: active versus held outbox rows, Desktop pending queue, verified peer receipt,
Agent response delivery, absence of repeated dispatch after terminal state, and transcript timing.
Historical unconfirmed delivery duration must be labelled as waiting, not model computation time.
