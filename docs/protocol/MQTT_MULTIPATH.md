# Automatic Multi-Broker Transport

Status: implementation in progress. Ingress hardening is integrated. The Desktop
and Android connection entry points now own the three-path pool in this development branch;
coordinated device acceptance remains unfinished. No
shipping installation or complete-feature release is claimed.

## Product Contract

- EMQX, HiveMQ, and Mosquitto are equal candidates. There is no default provider,
  saved preferred provider, manual selector, or manual failover button.
- Each Android application process and each Desktop backend owns one three-path
  pool. Windows, contacts, sessions, and tasks share it.
- Both endpoints will be upgraded and paired again. No legacy single-broker
  protocol compatibility branch is being added.
- Do not uninstall existing applications or erase current pairings automatically.
- Pairing identity, Signal, and the existing outer relationship AEAD remain in
  place. This change must not restore local attachment AES encryption.

## Catalog

`config/mqtt-multipath.json` is the source of truth. Run
`python tools/generate_mqtt_catalog.py` after changing it; use `--check` in tests.
The generator packages the same catalog for Python and Android without requiring
the repository config directory to exist in an installed application.

| ID | Host | TLS Port |
| --- | --- | --- |
| emqx | broker.emqx.io | 8883 |
| hivemq | broker.hivemq.com | 8883 |
| mosquitto | test.mosquitto.org | 8886 |

Connections use platform certificate validation and hostname verification. There
is no unencrypted fallback. The application's 1 MiB encoded-packet ceiling includes
the UTF-8 topic, MQTT headers, and QoS packet identifier. It is not a claim that
every public service accepts packets of that size. Actual path and peer limits
must further constrain scheduling.

Endpoint references: [EMQX](https://www.emqx.com/en/mqtt/public-mqtt5-broker),
[HiveMQ](https://www.hivemq.com/mqtt/public-mqtt-broker/),
[Mosquitto](https://test.mosquitto.org/). Mosquitto 8886 uses a public CA;
its 8883 listener requires a different CA configuration.

## Connection Ownership

`BrokerPool` / `MqttBrokerPool` owns independent TLS connections, retry state,
subscription grants, bounded pending publishes, and connection generations.
DNS or handshake delays on one worker cannot delay the other workers.
An old connection's callbacks cannot mutate a new connection's state.

Physical publish identifiers are `(broker_id, connection_generation, packet_id)`.
The pools expose independent logical publication identifiers and attempt IDs;
MQTT packet IDs must never be used as business message IDs.

Subscription intent is shared; actual grants are per path. Missing SUBACKs may be
retried without invalidating another path. Receive readiness requires all needed
exact subscriptions, not merely a successful TCP/TLS/CONNACK handshake.

## Authenticated Capabilities

`link_resume` is carried inside the existing authenticated relationship envelope,
not published in plaintext. Its fields are:

| Field | Meaning |
| --- | --- |
| transport_version | New automatic transport version, currently 1 |
| sender_fingerprint / receiver_fingerprint | Bind direction to the authenticated pair |
| route_epoch | Durable, strictly increasing, per-pair local revision |
| resume_id | Random 128-bit handshake identifier |
| issued_at_ms / expires_at_ms | Bounded freshness, currently at most five minutes |
| supported_brokers | Exactly the three new-protocol candidate IDs |
| receive_brokers | Paths whose receive subscriptions are active |
| max_encoded_packet_bytes | Receiver's bounded encoded-packet capability |
| multipath / chunk_acks | Required new-protocol capabilities |

Validation alone does not authenticate a payload. The caller must authenticate
the existing Link relationship and supply its expected sender and receiver.

Route state uses the existing Link delivery metadata database, not a second
business-delivery ledger. Persist the remote epoch before activating its paths.
An identical replay is a duplicate and cannot renew its expiry. An older revision
is stale; a changed announcement with the same revision is a conflict. Expired
capabilities stop being usable, but their epoch watermark remains. Only explicit
revocation or re-pairing removes the watermark.

The Android and Desktop canonical capability digest is cross-checked with the
same fixed contract vector in both test suites.

### Resume Acknowledgement

The existing relationship AEAD carries `link_resume_ack` with:

- `advertisement`: the responder's current `link_resume` object;
- `acknowledged_resume_id`: the initiating endpoint's live request ID;
- `acknowledged_route_epoch`: that request's exact integer epoch;
- `acknowledged_digest`: its canonical capability digest.

The receiver revalidates the current pair identity and ingress connection
generation before updating route state. An unsolicited/stale ACK is rejected
before route persistence. ACKs do not trigger another ACK. A newly discovered
common path expedites the endpoint's own outstanding resume instead of waiting
for its ordinary retry interval. Duplicate advertisements do not extend TTL.

Confirmation is generation-specific locally. A broker reconnect or changed
receiving set requires a fresh local epoch and request confirmation. A cached
publication descriptor cannot authorize a newer connection generation.

Pairing confirmation requires the entire relationship receive window on at
least one broker; the union of partial subscriptions across brokers is not
sufficient. Pairing bootstrap packets are explicitly classified by trusted
application code, not by a packet's untrusted `type` field.

## Scheduling

The table describes the target policy. The current Android and Desktop physical
adapters submit one packet per token; full logical-message hedging, racing, and durable
chunk scheduling are still being integrated above it. Policy unit tests alone
are not evidence that the complete product already uses these strategies.

Business paths are the intersection of local subscription-ready paths and the
authenticated peer's advertised receiving paths. An empty intersection queues
business work and triggers the authenticated resume process; it does not guess a
provider or silently relay through another user's Desktop.

| Traffic | Policy |
| --- | --- |
| Small critical control | Immediate race on healthy common paths |
| Normal small message / final | Best observed path with adaptive delayed copies |
| Progress | One path; obsolete progress must be coalesced by the sender |
| Attachment/wire chunk | One selected path per chunk; retry elsewhere if needed |
| Receipt | Prefer ingress, without an ACK-of-ACK race |

Unmeasured paths have equal scores with a per-process randomized tie-break.
Observed peer receipt latency and in-flight load influence ranking. Metrics expire
and are cleared on network change. A PUBACK does not supply peer-delivery latency.

The 12-packet global budget is not multiplied by three. Two slots and byte capacity
are reserved for control/final/receipt traffic, including within each peer's byte
quota. Chunk allocation is demand-driven, not batches of fixed round-robin sends.

## Delivery Invariants

- `BROKER_ACKED` releases the physical send reservation, not the business outbox.
- Only a verified, durably accepted peer receipt ends a business message race.
- Receipts bind the authenticated peer, stable message ID, immutable content hash,
  and accepted attempt ID. A packet with the right message ID alone is insufficient.
- On the first valid peer receipt, cancel unsent copies. Already-sent copies keep
  their physical budget until PUBACK or a path failure; their bytes cannot be unsent.
- Race copies must share the same immutable Signal ciphertext. Authentication,
  hash binding, and durable duplicate claims must precede business side effects.
- Signal receive processing remains serialized per relationship across all paths.
- The existing Run Kernel owns task identity and side-effect recovery. A transport
  receipt must not create another task or repeat an uncertain external effect.
- Attachment chunks share one durable assembly and bitmap. A chunk receipt is not
  a complete-file receipt; final hash validation precedes preview/open/save.

## Integrated Ingress Boundary

Android's real MQTT callback now admits packets through `MqttInboundRoutePool`.
Its up to four lazily started workers rotate fairly among configured Signal identities.
An idle peer leaves no retained lane; workers expire after five idle seconds.
The default bounds are 1,024 retained packets / 32 MiB globally and 64 packets /
8 MiB per identity, including the currently executing packet. Admission rejection
does not emit an application delivery receipt; the durable sender must retry.

`MqttInboundBindings` maps all configured rotating mailbox aliases to the same
Signal identity. Unknown and ambiguous aliases are rejected before queueing.
Desktop's existing bounded ingress pool now also serializes by configured Signal
identity, rather than a route ID that can vary between relationships for that
identity. One-time pairing topics have separate bounded lanes.

Desktop validates both application endpoints before binding a message ID to its
immutable envelope hash in the existing Link delivery database. The database
primary key is `(sealed configured pair, message_id)`; a conflicting body or
conversation is rejected before Blob acceptance or any business dispatch. This
local content digest includes the envelope headers, including timestamps. Retry
copies reuse the original envelope/ciphertext, not a rebuilt envelope with a new
timestamp. Changed content requires a new transport message ID.

The hash binding is not itself a task claim. Android now shares an atomic Signal
and durable-inbox transaction; Desktop shares a Signal/receive-journal SQLite
transaction and hands full bodies to the Python delivery database before releasing
the JVM copy. Both preserve authenticated scope and immutable content. The
Desktop body extension is not a second task ledger: the existing Run Kernel still
owns execution and uncertain external effects.

Desktop now hands stored bodies to the actual bridge consumers. The same delivery
transaction creates the full body and an indexed RX_STORED dispatch row. A replay
of known ciphertext reloads that body, rather than skipping business dispatch
based only on a message-ID claim. Dispatch ownership uses bounded OS file locks;
process death releases ownership, not an elapsed lease timer. Known idempotent
handlers may resume. An interrupted operation without a verified replay contract
remains uncertain and is not automatically executed again.

The existing service retry loop admits at most 16 stored messages / 4 MiB per
pass into the same bounded per-identity ingress pool, including while disconnected.
Admission tokens expire for queue retry, but do not prove a handler has exited.
The pending-only SQLite index avoids scanning completed history every second.
Task requests retain their original identity and reuse the existing task manager.
Transport RX_STORED is not TASK_ACCEPTED or RUN_FINISHED.

Completed-body retention/compaction, cancellation execution-generation fencing,
ordered wire acceptance, and full physical-attempt receipt integration are still
required before multi-path delivery activation. The existing receive ACK now
uses `signal-wire-sha256-v1`, a cross-platform digest of immutable Signal wire
fields, not the local JSON application-envelope digest. The outgoing consumer
requires this digest, stable message ID, `RX_STORED`, and the current pair/key
binding persisted in the outbox. Local JSON hashes still enforce content
conflicts independently. The Desktop small-message dispatcher and peer-RTT
accounting now use this frame in the actual durable publisher/bridge ingress.
Android's symmetric small-message dispatcher is also integrated. Wire-fragment
bitmap and missing-only retry are described below; whole-artifact acceptance
and throughput-aware striping remain pending.
See [durable receipt verification](../testing/MQTT_DURABLE_RECEIPTS_20260913.md)
and [Desktop hedge verification](../testing/MQTT_HEDGED_DISPATCH_DESKTOP_20260913.md).
Fair local Signal locks avoid thread
starvation but do not guarantee ordering across independent brokers.

### Adaptive Small-Message Hedge

Ordinary small messages and final results use a primary path and delayed copies.
The delay uses the current peer's verified receipt p90 multiplied by 1.5, within
the shared catalog's bounds. Twenty recent samples are required. Before the
primary has twenty samples, observations from eligible healthy common paths of
the same peer can meet that threshold; other peers, expired observations and
paths outside the candidate set cannot contribute. A mature primary's own
window takes precedence over the aggregate. Network changes discard old speed
assumptions. Below the sample threshold the conservative catalog default remains.
Small stop/cancel controls race immediately and are not delayed by this estimate.
The unsampled backup interval is 2000ms; the separate unknown-path ranking
estimate remains 500ms. Increasing the backup interval must not silently alter
ranking. Detected physical failure expedites backups without that wait. See
[cold-hedge verification](../testing/MQTT_COLD_HEDGE_20260913.md).
See [native latency evidence](../testing/MQTT_NATIVE_LATENCY_20260913.md) for the
owned-network measurements and the remaining performance acceptance boundaries.

### Deferred Stored Receipts

Stored small-message attempt receipts that cannot yet use a confirmed route
are retained by the existing maintenance owner: at most 1,024 proofs globally,
64 per peer, a 500ms minimum retry interval and a fixed 30s lifetime. Pair/key,
message/hash and current confirmed path generation are revalidated on each send.
This local acceleration is not a second durable delivery ledger; expiry, process
death or subsequent packet loss still use the original sender replay and stored
inbox proof. Receipts do not request another receipt. See
[receipt recovery verification](../testing/MQTT_RECEIPT_RETRY_20260913.md).

## Durable Wire Fragment Ingress

Both actual receive paths now persist authenticated `signal-chunk` fragments in
their existing Link/Signal databases. The local storage scope includes pair/key
identity and does not change with broker or rotating Topic. A domain-separated
manifest hash binds transfer SHA-256, fragment count, total byte count, and both
application endpoints. Strict fragment hashes and final-wire validation precede
the original Signal/inbox transaction. Only that committed inbox's matching
wire proof authorizes release of completed fragment bytes.

Pending reserved storage is bounded at 16 transfers / 32 MiB, per pair at eight
transfers / 16 MiB, with fixed eight-day retention. Existing fragment geometry
and application attachment IDs are unchanged.
See [fragment verification](../testing/MQTT_DURABLE_CHUNKS_20260913.md).

## Wire Fragment State Exchange

The current pair-AEAD envelope carries these controls; none goes into chat or
the model prompt. Only authenticated current pair identity and current subscribed
connection generations may update the transfer state.

- `_mqtt_chunks` on each `signal-chunk` contains a version-1 query.
- `link_chunk_probe` carries that query without fragment bytes.
- `link_chunk_state` returns the query plus durable receiver state.

Query fields are `version`, `transfer_id`, `manifest_hash`, `chunk_count`, and a
fresh 32-lowercase-hex `request_id` for each existing retry batch. The transfer ID
is the existing complete raw-wire SHA-256, not a new task or attachment ID.
The manifest hash is domain-separated and binds total size, count and endpoints.
Both hashes are 64 lowercase hex characters. Count remains bounded at 96.

A state adds `store_epoch` (32 lowercase hex), monotonic integer `revision`, and
canonical padded Base64 `stored_bitmap`. Bit index zero is the least-significant
bit of byte zero; the byte count is exactly `ceil(chunk_count / 8)` and unused
high bits must be zero. The unknown-transfer response has all-zero epoch,
revision zero, and empty bits; querying it allocates no incoming byte storage.

The existing Link database stores only outgoing bitmap, current request, receiver
epoch/revision and per-index attempted-path bits. The existing durable outbox
still owns the immutable Signal wire. Sender metadata expires after seven days;
retries do not extend retention. Admission is capped at 65,536 manifests globally
and 4,096 per pair. Receiver complete-proof metadata has the same count caps.

Only a solicited state for the exact current query can change outgoing bits.
The first state of a fresh batch can report receiver storage reset. Subsequent
states must keep that receiver epoch and advance revision; an exact duplicate
is harmless, an older revision is ignored, and different bits at the same
revision are rejected. A newer verified revision may retract a corrupted bit.
The receiver validates stored fragment hashes before reporting its bitmap.

Each retry batch selects only missing indices. A path attempt is persisted before
physical publication; a retry prefers another healthy common path using the
existing policy and total reservations. A full bitmap causes a small probe, not
full re-upload and not a business completion claim. Current scheduling still
uses the existing retry cadence. Chunk scheduling now considers peer latency,
physical in-flight bytes and unconfirmed chunk bytes, together with a smoothed
rate derived only from committed, solicited, pair-authenticated bitmap feedback.

An observation binds pair, transfer, query nonce, index, broker and connection
generation. Only unambiguous first attempts contribute speed samples; retries,
duplicate possible paths, obsolete queries and changed generations do not.
Broker PUBACK releases physical slots but does not erase unconfirmed chunk load
or count as successful peer delivery. Rates aggregate newly confirmed encoded
wire bytes by broker per feedback batch. They include receiver persistence,
feedback-window and return-path latency, not raw link bandwidth or attachment
goodput. An EWMA weights the latest sample 25%; at least three samples are
required before replacing the configurable 256 KiB/s cold estimate. Observations
expire after 30 seconds, rates after five minutes; network changes clear both.
The existing 4,096 observation cap and 10,000 configured-peer cap remain.

Partial bitmap feedback coalesces by pair/transfer/query over a 200ms window,
preserving the first deadline and latest revision. The existing 250ms pool
maintenance tick flushes up to 16 due entries, without new timers or workers.
Completion and explicit probe responses bypass that window and cancel the
queued partial response. The queue is capped at 1,024 entries globally and 64
per pair; identity replacement or removal clears its pending feedback. A delayed
callback revalidates the current pair and path before publication. These are
bounded scheduling intervals, not guarantees while Android suspends execution.

After original inbox commit, fragment bytes are removed while a compact proof
remains for the receiver's fixed eight-day retention. A probe can retry a complete
but interrupted Signal handoff from retained local bytes. For a completed proof,
the receiver repeats the original business receipt only if the current inbox
still proves the same message ID and Signal-wire hash. A bitmap alone never
retires the business outbox or claims `RX_STORED`, `TASK_ACCEPTED`, or `RUN_FINISHED`.

## Verification Boundary

Host unit tests and low-volume public loopbacks are not application acceptance.
Public shared brokers must not be used for concurrency, capacity, chaos, or power
benchmarks. Those require owned or explicitly authorized broker infrastructure.
No threefold bandwidth claim follows from having three connections on one NIC.

Android Doze, process death, and network restrictions remain real platform limits.
The application must persist work and resume when allowed rather than promise an
always-running UI or unrestricted background process.

See the engineering progress record for activated paths, pending integration, and
the evidence available so far.
