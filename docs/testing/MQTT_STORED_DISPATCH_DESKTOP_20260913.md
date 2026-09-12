# Desktop Durable Receive Dispatch

Date: 2026-09-13.
Worktree: GalaxySSI-multi-broker-20260912.
Scope: actual Desktop inbound routing and service-owned stored-message recovery.
This is a development checkpoint, not three-broker product acceptance.

## Implemented

- The existing delivery transaction saves both the authenticated full body and
  its RX_STORED pending-dispatch record. No second task ledger is created.
- Known-ciphertext replay loads the durable body and consults dispatch state;
  an old ID-only claim no longer drops a task before it reaches its consumer.
- Dispatch ownership is protected by a bounded set of 256 OS file locks.
  A live owner blocks another handler. Process death releases ownership.
- States are stored, running, dispatched, retry, uncertain, and rejected.
  Dispatch completion means handoff to the existing consumer, not run completion.
- Known idempotent handlers can be retried; unknown interrupted external effects
  remain uncertain. Original task/conversation/turn/source identity is retained.
- Background replay uses the existing service loop and per-Signal-identity worker
  pool. Each pass admits at most 16 messages and 4 MiB, subject to existing global
  and per-identity queue budgets. It does not require a new incoming packet or an
  online MQTT connection.
- Queue admission tokens use a five-second scheduling deadline. This is not a
  handler lease and is never evidence that a running handler has died.
- A pending-only SQLite index avoids scanning completed history on each pass.
- RX_STORED receipts include canonical content hashes. A receipt is never itself
  acknowledged; a failed receipt publish does not prevent a saved task handoff.
- Revoked/changed peers and expired envelopes cannot start recovered work.
- Business-payload enrichment does not mutate the canonical stored envelope.
- The 426-line business dispatch body was extracted without semantic changes,
  except removing message-content excerpts from normal logs.

## Verification

Final backend run: 262 tests, zero failures/errors, 44.692 seconds.
Local log: build/mqtt-dispatch-final.log.

The set contains 34 focused dispatch tests (16 state/ownership tests and 18
actual bridge tests), plus existing transport, route, Signal handoff, Blob,
phone-tool, recovery-page, timing, and process-recovery regressions.

Verified cases include:

- Real child-process termination while owning a dispatch lock, followed by
  acquisition and recovery in another process.
- Three concurrent copies produce one business dispatch.
- Stored work resumes without a fresh network packet.
- Known-ciphertext replay before handoff is recovered instead of skipped.
- Completed duplicates are acknowledged without repeating business dispatch.
- Unknown interrupted tools and unfenced interrupted cancellation are not
  blindly replayed.
- ACK delivery failure, queue loss, retry backoff, explicit revocation, corrupted
  or absent body, expiry, and endpoint mismatch.
- Existing Blob persistence-before-ACK order and cross-phone tool isolation.
- Existing task latency hooks do not count duplicates as new work.
- Query-plan verification uses the pending index without a completed-body scan
  or temporary sorting tree.

The real HTTP/JVM handoff tests also passed: restart before and after the Python
commit preserved identity/body without a second decrypt. The sidecar recovery
sample was 3922 ms; maximum cached health-read latency was 0.101 ms. These are
single isolated recovery observations, not transport latency percentiles.

## Remaining Boundaries

Production Android and Desktop still use their original single-broker entrypoints.
Three-broker lifecycle, authenticated resume/route negotiation, physical-attempt
accounting, receipt validation, and durable fragment scheduling are not activated.
The receipt producer's hash field is not proof of end-to-end hash-bound ACK
validation; the sending side still needs that integration.

Completed-body compaction/retention and complete external-effect reconciliation
remain open. In particular, cancellation needs an execution-generation fence
before interrupted cancels may be replayed automatically.

No production App install, Desktop replacement, or PR occurred for this
checkpoint. The latest designated phone is S20U, SM-G9880, ADB R5CN319CESA.
Only its connection inventory was read. S26U and SM-T575 were not operated.
No public-broker load test or S20U three-path acceptance is claimed.
