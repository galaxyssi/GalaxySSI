# Fair Collaboration Evidence Recovery

## Problem

A model reply and its authenticated tool evidence have separate delivery paths.
The Android member finalizer deliberately waits for pending evidence imports.
Previously the recovery worker imported entire archives serially, so a slow or
large archive could delay unrelated members. A previous real trial showed a
long Desktop-completion-to-member-finalization interval, but its logs did not
separate transport, evidence import and finalization. That interval alone is
not proof that the broker or this scheduler caused all of the delay.

## Change

- Background recovery has two I/O lanes, preserving the existing pending-job
  page size and durable scheduler cursor. This is not a model concurrency cap.
- Each archive gets up to four network queries per slice, then rejoins the end
  of the current batch. There is no new total observation or attempt limit.
- Verified pages and index remainders survive a slice, cancellation and reopen.
  Already committed tool operations are never rerun by this read-only path.
- Only budget yields are immediately requeued. Transport failure, pause or an
  unsealed archive defers the job to the existing recovery/backoff mechanism.
- One job's storage failure does not cancel unrelated imports. Coroutine
  cancellation still propagates, and unstarted jobs are not marked as claimed.
- Live foreground refresh retains its existing deadline and shares the same
  per-job import gate. The two-lane bound applies to background recovery, not
  every foreground read in the application.

The member finalizer still waits for pending evidence. Pairing, exact task and
generation identity, group membership, pause/stop, page hashes, original scope,
publication receipts and independent-review requirements are unchanged. An
imported tool observation is not automatically a scientifically verified claim.

## Diagnostics

`GalaxySSIEvidence` records content-free query mode, source-message identity,
outcome and elapsed milliseconds, plus evidence-wait start/end and whether that
wait settled. No prompts, document contents, credentials or evidence bodies are
included. These markers let a later real trial distinguish a model delay from
phone-side evidence waiting; cancellation is not reported as settled delivery.

## Verification

Focused unit and S20U device verification cover:

- A held response for one member while another member's evidence finishes.
- Large archives rotating behind small jobs and no same-pass offline retry.
- Two-lane resource bounds, cancellation and per-job error isolation.
- Byte-exact resume across store reopen without re-reading verified pages.
- More than one index page, with no total observation limit introduced.
- Existing authentication, scope, pause, revocation and corruption rejection.

Device fixtures use dedicated groups and synthetic read-only protocol replies;
they do not call a model or broker, replay research, or operate physical tools.
Real-network tail latency and complete autonomous peer verification still need
a fresh bounded trial. Do not report these fixture results as that acceptance.

### Recorded run (2026-10-08)

- Android `1.4.96` / `1181`, installed as an upgrade on SM-G9880 (S20U).
- 46 unit tests passed: recovery scheduler (5), remote evidence (36), live
  evidence synchronization and shared import gate (5).
- Debug application and instrumentation APK builds passed.
- Five targeted device cases passed in 4.055 seconds. Two additional process
  checkpoint phases passed, with a force-stop between seed and recovery and
  different process IDs confirmed. Recovery rejected any request for the page
  already persisted by the seed phase, then checked the byte-exact original.
- Repository checks and whitespace checks passed.
- No model calls, physical actions or old research replays were made by these
  tests. Test groups were removed by their fixture cleanup.
