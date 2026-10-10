# Bounded transient control path racing

Small caller-retried collaboration query packets now use each currently
authorized zero-delay path selected by the existing multipath policy. Previously
the single-physical-packet compatibility publisher returned after the first
accepted path, even though the control policy selected more than one.

Only authenticated transient control packets within the existing small-packet
limit use this path. They are encrypted once and the identical outer-wire bytes
are reused; there is no new logical request, durable outbox or retry owner. Each
physical copy independently reserves the existing global/peer capacity and
revalidates the original pair and broker generation immediately before sending.
Congestion may admit fewer copies. A changed or failed path cannot authorize a
replacement generation and does not prevent other still-authorized paths.

Receipts, ordinary messages, large evidence and fragmented payloads retain their
existing strategy. The returned token denotes one accepted physical publication,
not peer receipt or task completion. The authenticated receiver's existing
ciphertext/message deduplication prevents duplicate application dispatch.

Regression coverage uses the real route exchange, policy and encrypted bridge
entrypoint with an in-process broker fixture. It covers identical copies, bounded
capacity, one-path failures, revocation and generation races, scoped broker ACKs,
and the unchanged single-path fallback. Existing durable receiver tests cover
concurrent duplicate dispatch suppression. Public-network timing is a separate
device acceptance result and cannot establish a scientific team advantage.

Admission failures now retain a bounded reason code for packet/byte capacity,
tracking capacity, invalid identity, or path-generation failure. The Boolean
reservation API and all limits are unchanged; structured collaboration feedback
uses the same allowlisted codes and never exposes payloads.

The S20U read-only probe remains failed: some responses were accepted late and
the live log also exposed inflight packet admission refusals. The Android
transient encrypted query path still classifies packets as ordinary traffic and
requires its own integration. This Desktop change does not claim full bidirectional
acceptance or eliminate all public-network delays. No model task was rerun.
