# Automatic Multi-Broker Transport

Status: implementation in progress. Ingress hardening is integrated; the three-path
connection pool is not yet activated in the application connection entry points.

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

## Scheduling

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

This binding is not a task claim, a durable full-message receipt, or an additional
task ledger. It stores no plaintext payload and does not enable receipt races by
itself. Atomic inbox/ciphertext/receipt recovery and Android's scoped durable
content binding are still required before three-path activation. Existing
time/count-pruned Android replay records must not be treated as that final ledger.

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
