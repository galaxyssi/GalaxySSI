# Android #3031: Encrypted Source Replacement

Reference: Android PR #3031, pinned merge
`2c4a764154e64871a130e7e7e58229eb8de230bb`. This is not a port of
the later #3035 preparation-outside-writer implementation.

## Implemented Boundary

- `AgentKnowledgeSourceStaging` consumes the incoming producer once. A fresh
  per-call AES-GCM key encrypts each record; a separate ephemeral HMAC key hides
  stable IDs in the scratch index. Job, side and token are authenticated. Neither
  key is persisted. Files use complete protection and private permissions.
- First valid incoming ID wins. Wrong-source and empty-title/body candidates are
  skipped; blank IDs, authentication failure and count mismatch fail closed.
- Metadata pages contain at most 64 tokens. Decoded bodies are visited one at a
  time. This does not bound the size of one decoded record or prove a measured
  process RSS limit. Closing the scratch removes its owned random directory.
- `AgentKnowledgeDatabase.replaceSource` stages incoming records before taking
  its writer lock, then prepares old records and applies replacement in one
  canonical SQLite transaction. The old-source scan uses a composite source/key
  index. Every incoming ID is checked for cross-source ownership before mutation.
- The oldest existing record's access policy applies to the replacement; equal
  timestamps use persistent catalog HMAC ordering. Empty summaries fall back to
  a content prefix. Equality ignoring only update time retains the old record.
- Unchanged canonical ciphertext, source headers, browse revision, vector
  checkpoints and feed stay untouched. Changed/deleted IDs remove only their
  FTS/vector rows, publish model removal events and enqueue replacement IDs for
  registered models. Unrelated sources are not rewritten.
- Only the selected source header is rebuilt and the browse revision advances
  once if there was a change. Failure or cooperative cancellation before COMMIT
  rolls back canonical rows, headers, FTS, vector queues and feed changes.
- The existing Store replacement API (also used by document attachment import)
  now calls this transaction. Its compatibility array is decoded before COMMIT,
  so failure cannot commit a catalog with an unpublished stale cache. Publishing
  that committed cache bypasses the legacy `didSet` whole-database replacement.
- Attachment import uses a count-oriented entry and a reiterable chunk sequence:
  one count pass, then a one-shot incoming record producer, without a paragraph
  or chunk body array. The legacy array-returning entry remains compatible.
- Previous/current source observations now fold records in encrypted external
  SQLite order (chunk, raw UTF-16 ID). Only two small metadata keys are decrypted
  during collation. Reads authenticate key/body identity, chunk, counts and strict
  order; collation errors fail closed. Encoded metadata keys over 64 KiB fail
  closed instead of allocating an unbounded sort-key buffer.
- Content SHA-256 is incremental. Tags retain only the smallest twelve; allowed
  Agent ID union/deduplication/order uses an encrypted scratch index. Only the
  bounded normalized prefix consumed by the existing access fingerprint is kept.
  Allowed-ID comparison preserves existing Swift string equality/ordering; raw
  source IDs use Android UTF-16 order, also applied to the legacy snapshot oracle.
  This deliberately corrects the previous non-ASCII source-ID ordering.
- A source-level event (not one event per chunk) is encrypted into a durable
  outbox in the same canonical transaction. Store exposes pages of at most 64
  envelopes and receipt-based acknowledgement. Random receipt identity is
  authenticated with the event hash: A-to-B-to-A retains distinct deliveries,
  and acknowledging the first A cannot delete the later A. Replay/no-op does not
  enqueue another event. Precommit failure rolls the outbox back with the source.

## Remaining Parity Work

This is the transaction and production-adapter portion of #3031, not completed
corpus-scale memory or observation parity:

- Startup, other legacy mutations and the UI still retain the complete knowledge
  array. Document extraction still materializes its bounded text input. The
  precommit UI adapter still materializes this source's decoded cache array;
  the count API does not remove that existing UI requirement.
- The prior extractor had no production publisher. The replacement path now
  durably produces source observations, but automatic global-runtime consumption
  is not wired: its current runtime has no matching event ingestion boundary.
  Pending/acknowledgement APIs are a durable handoff, not a claim that global
  model processing, lifecycle sanitization or projections have consumed events.
  Outbox storage grows until a consumer acknowledges receipts.
- Legacy `replaceAll` writers (including restore/reset and access-policy edits)
  atomically invalidate pending source observations. They do not yet produce
  equivalent durable lifecycle events. This prevents stale summaries from being
  consumed after policy changes, but is not a continuity/retraction guarantee
  across legacy bulk mutations or already-acknowledged global projections.
- Old-source preparation still holds the writer transaction, matching the pinned
  #3031 boundary. There is no separate prepare/revalidate protocol yet.
- There is no process-death scratch orphan sweeper, hard key zeroization
  guarantee, or hostile same-container filesystem
  actor guarantee. Existing external-payload physical reclamation is unchanged;
  a rolled-back write may leave an encrypted orphan for existing maintenance.
- Android capacity, latency, power-loss and physical-device measurements do not
  establish iOS acceptance.

## Verification Scope

Twenty-four synthetic XCTest methods are authored for encryption, duplicate handling,
corruption, blank identity, multi-page replacement, ownership preflight, two rollback
boundaries, ACL ordering/ties, no-op preservation, targeted vector invalidation,
empty replacement, producer failure, normalization, cancellation, Store wiring,
stream/array observation equivalence, UTF-16 ordering, close-during-visit safety,
outbox reopen/exact receipt acknowledgement/rollback/corruption, bulk invalidation
and count import.
They have not been compiled or executed. Source guards and the iOS project
structure check are separate static checks, not native acceptance. No IPA,
real-device evidence or reports are included.
