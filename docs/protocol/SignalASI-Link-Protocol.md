# SignalASI Link Protocol v2

## Status

SignalASI Link Protocol v2 is the only supported public-relay protocol. It is a
hard cut: implementations do not import earlier pairing registries, subscribe
to earlier topics, publish fallback messages, or reactivate earlier sessions.
Every device must pair again after upgrading to v2.

Normative terms such as MUST, MUST NOT, SHOULD, and MAY are requirements.

## Threat Model

The MQTT broker, network path, unrelated subscribers, and unpaired endpoints are
untrusted. They may observe, copy, delay, reorder, replay, or drop traffic.

v2 is designed so the public broker cannot learn product roles, platform names,
device names, identity fingerprints, contact IDs, directions, message types, or
plaintext. It still observes source IP addresses, connection timing, topic
activity, QoS behavior, and padded packet-size buckets. A direct MQTT connection
is therefore metadata-resistant, not anonymous. Hiding IP and timing correlation
requires a separate privacy relay or anonymity network.

## Cryptographic Layers

Every established relationship uses two independent layers:

1. Signal Protocol protects application identity and message content end to end.
2. An outer AES-256-GCM packet protects Signal envelope shape, protocol fields,
   chunk metadata, and message type from the broker.

The outer key is derived from a 256-bit relationship secret with domain-separated
HMAC-SHA-256. Nonces are random 96-bit values. Plaintext is padded to one of four
buckets: 1 KiB, 4 KiB, 16 KiB, or 40 KiB. The MQTT payload is unpadded Base64URL.

Before a Signal session exists, the one-time QR secret protects the bootstrap
claim with the same outer packet construction.

## Public MQTT Surface

Every public topic is exactly one unpadded 256-bit Base64URL value:

```text
[A-Za-z0-9_-]{43}
```

Topics contain no slash, prefix, version, product name, endpoint role, platform,
direction, account, device, contact, or fingerprint. MQTT client IDs are random
128-bit Base64URL values and rotate whenever a client object is recreated.

Business and control packets use QoS 1, clean broker sessions, and `retain=false`.
The encrypted local outbox, not the broker session, owns durable delivery.

## One-Time Rendezvous

Creating a QR offer generates independent random values:

- a 256-bit pairing token;
- a 256-bit pairing secret;
- an opaque rendezvous topic derived as
  `HMAC(pairing_secret, "rendezvous-topic")`.

The offer also carries the signed endpoint identity, Signal pre-key bundle,
creation time, and requested Desktop access profile. It expires after ten
minutes. The receiver verifies the identity binding, signature, bundle
fingerprint, derived rendezvous topic, and freshness before publishing a claim.

The claim is outer-encrypted with the QR secret. Its plaintext contains a fresh
control UUID, one-time token, signed identity card, source identity, target
identity, and timestamp. It MUST NOT contain a relationship secret, internal
route ID, reply topic, platform route, or separate unsigned Signal bundle.

The QR owner atomically binds the offer to the first valid identity. An identical
QoS retry from that identity may replay the encrypted confirmation, but it cannot
create a second relationship. A different scanner is rejected. The bound offer
is deleted at expiry.

## Relationship Derivation

Both peers independently derive the same relationship secret:

```text
relationship_secret = HMAC(
  pairing_secret,
  "relationship" || sort(identity_fingerprint_A, identity_fingerprint_B)
)
```

Each installation also creates a random 128-bit local route record ID. That ID
is local database state only; peers do not exchange it and it is never an MQTT
topic.

Directional mailbox topics are derived from the relationship secret, ordered
sender and receiver fingerprints, and a six-hour epoch:

```text
topic = HMAC(
  relationship_secret,
  "mailbox" || sender_fingerprint || receiver_fingerprint || epoch
)
```

The sender publishes to the current epoch. The receiver subscribes to current,
previous, and next receive epochs, then refreshes subscriptions immediately after
each epoch boundary. This tolerates clock skew and uninterrupted long-running
connections without exposing a stable mailbox.

## Android-to-Desktop Pairing

The Desktop exposes a compact QR at `/signalasi/verify`. Android normalizes and
validates it locally, derives the relationship secret, creates local route state,
and publishes the outer-encrypted claim. Desktop atomically consumes the token,
validates the claimed identity and access grant, installs the Signal bundle, and
sends confirmation through the new relationship mailbox.

Pairing a second phone creates an independent relationship. It does not rotate or
invalidate another phone. A configured mobile cloud-model API does not depend on
a Desktop relationship and remains available without pairing.

## Android-to-Android Pairing

The QR owner subscribes only to its short-lived rendezvous topic. The scanner
creates a pending friend request and subscribes to its derived receive window.
The QR owner derives the same secret from the bound QR session and scanner
fingerprint, creates its own local route record, stores the request under New
Friends, and sends a confirmation on the relationship mailbox.

Both users must approve the pending request before ordinary messages can be sent
or displayed as a contact. Deleting a contact removes its relationship material;
communication requires a new QR offer and a new relationship.

## Encrypted Application Envelope

After outer decryption and Signal decryption, the application envelope contains:

```json
{
  "protocol": "signalasi-link",
  "version": 2,
  "message_id": "UUID",
  "conversation_id": "UUID or empty",
  "source_id": "authenticated identity",
  "target_id": "logical encrypted destination",
  "reply_to": "UUID or empty",
  "sent_at": 1780000000000,
  "expires_at": 1780604800000,
  "payload": {}
}
```

Receivers validate the exact major version, UUID, time window, authenticated
relationship identity, target identity, payload limits, and message replay state
before dispatch. Unknown or malformed traffic fails closed.

## Multiplexing

One directional relationship mailbox carries all encrypted application classes:
chat, task events, acknowledgements, capability updates, control operations,
attachments, voice, and artifacts. Public topic names never encode a channel.
Application routing occurs only after both cryptographic layers are opened.

## Reliability and Fragmentation

The sender persists an encrypted outbox entry before publishing. The receiver
persists the application `message_id` before side effects and returns an encrypted
acknowledgement with an explicit `transport_message_id`. v2 does not interpret
`source_message_id`, `reply_to`, or other earlier fields as transport ACKs.

Large inner Signal envelopes are split into bounded wire chunks before outer
encryption. Every chunk includes a transfer UUID, index, count, exact byte length,
chunk SHA-256, and whole-message SHA-256. The receiver accepts identical
duplicates, rejects conflicting duplicates, enforces count and byte budgets, and
dispatches only after complete hash verification. Outer packet limits are checked
after padding and encryption.

## Revocation

Revocation is scoped to one relationship. The revoking endpoint attempts one
non-retained encrypted notification, then removes the registry record, Signal
session, queued route data, and task/tool sessions owned by that relationship.
Other relationships remain unchanged. Re-pairing always creates fresh secret
material; old mailboxes are never reactivated.

## Stored State

Relationship secrets, fingerprints, local route IDs, rendezvous sessions, and
accepted control UUIDs are encrypted at rest. A registry with an unsupported
schema is discarded rather than migrated. Corrupt encrypted state fails closed
unless a valid encrypted recovery copy exists.

## Limits and Deployment

- Pairing/control freshness: 10 minutes.
- Mailbox epoch: 6 hours; receive overlap: one epoch each side.
- Application envelope: 512 KiB.
- Plain text: 128 KiB UTF-8.
- Outer MQTT packet: 60 KiB Base64URL.
- MQTT wire chunks: bounded count and aggregate size.
- Default application expiry: 7 days.

TLS certificate validation is mandatory. The public EMQX broker is suitable only
for development and reachability testing. Production should use authenticated
broker access, rate limits, abuse controls, and route-scoped authorization where
available. These controls complement end-to-end encryption; they do not replace
it.

## Version Rule

Unknown major versions are rejected. A future change to key derivation, mailbox
meaning, wire encryption, identity binding, or required fields requires a new
major protocol and a fresh pairing. There is no v1 compatibility path.
