# Late collaboration evidence recovery

Android v1.4.119 keeps a bounded correlation for a read-only Desktop evidence
query after its caller's wait expires. An authenticated reply arriving later can
be used by the next matching recovery slice. Previously it was discarded and a
new nonce forced another round trip, even when the original evidence was ready.

## Contract

- Retries reuse only an inactive query with the same authenticated Desktop,
  route, conversation, task, turn, contact, source message, provider, execution
  generation and complete selector (mode, cursor, evidence hash/ID, page, inline
  allowance). Concurrent active callers retain separate ownership.
- Contract, nonce, mode, status, complete identity and page bindings are still
  checked on receipt. Import still checks original hashes, page hashes and the
  current persisted access/binding. A reply alone never imports evidence or
  changes a task, starts a model, resumes work or repeats an effect.
- A successful late reply can be consumed without another publication. A retry
  still waiting for its reply republishes the original read-only nonce.
- Explicit coroutine cancellation and rejected publication discard that query.
  Pause, stop and access checks remain in the existing import/recovery layer.
- Inactive correlations expire after two minutes, with at most 128 records and
  2 MiB of retained response bodies. These are memory-retention bounds, not a
  research-step or task limit. Expiry/eviction falls back to ordinary recovery.
- Retained replies do not survive process death. Already verified pages and
  the durable import cursor do, using the existing store. A new process makes
  fresh queries. A late non-final index is not reclassified as a final archive.

## Verification

Unit coverage exercises late delivery before/during retry, exact selector
matching, all identity and page checks, duplicates, cancellation, expiry,
separate concurrent ownership, body/count bounds and fresh queries after
eviction. Existing importer tests cover invalid/corrupt originals, revoked
access, sealed/live indices, page resumption and evidence-ledger binding.

The device fixture delays both an index and a page, then checks that the original
bytes reach the real encrypted ledger with no repeated successful query. It uses
synthetic local data, no broker, model or existing user task. This test does not
establish that all public-broker latency or collaboration transport failures are
fixed, or that scientific collaboration quality improved.

## Local result (2026-10-09)

- Final targeted unit run: 114 tests, no failures, errors or skips, including
  immediate coroutine consumption and late-response ownership tests.
- S20U SM-G9880: six local device scenarios passed. Two parameter-gated methods
  were not exercised in that batch; the checkpoint seed/recover method then
  passed in separate application processes (PIDs 6099 and 6143).
- Installed Android 1.4.119 / 1204; APK SHA-256:
  `7523f9cc40af51dfdae25e001dbe9207604570002fd42f3fad91bd954718bda1`.
- Repository structure, text policy, Kotlin source-size and diff checks passed.
- No new real-model run was performed after this fix. Desktop source and UI are
  unchanged; this does not claim complete live-network recovery acceptance.
