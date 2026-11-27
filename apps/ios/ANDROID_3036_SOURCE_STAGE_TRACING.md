# iOS source replacement stage tracing (Android #3036)

Reference: Android merge `dfe37f35ad9cf00b5424702f9f831334c496c492`.
This increment adds diagnostics to the existing checked document/web import
route. It does not change encryption, schema, source policy, transaction
visibility, ASR, inference or the model lifecycle.

## Scope and ancestry

The branch starts at #4623 (`40a4e93b7`), which includes #4621/#4619 committed
lexical/vector reads and #4616 streamed replacement/observation. Those changes
are prerequisites, not newly delivered by this tracing increment. The #4617
operation-key memo and the separate primary-storage publication chain are not
included. The PR is based on `main`; its full diff includes these prerequisites
until they land. No approval, merge or native acceptance is implied.

## Timing contract

Seven pairs use the existing `phone_runtime_knowledge_source_*_started` and
`*_finished` contract, summarized as `*_ms` P50/P95/P99 metrics:

| Phase | Actual iOS boundary |
| --- | --- |
| total | Checked Store import: eligibility, chunking, staging, preparation, commit, UI cache publication, index scheduling, settings save and scratch cleanup |
| stage | Scratch creation, one-shot producer consumption, encrypted incoming staging and sealing |
| prepare | Committed read admission, source generation, authentication of old records, policy selection and previous staging |
| commit | Prepared claim, writer admission, generation fence, ownership, apply, observation/outbox, precommit cache materialization and durable commit |
| ownership | Current incoming identity ownership checks before mutations |
| apply | Staged previous/incoming traversal, policy normalization, canonical/FTS/vector/header changes and stage finalization |
| observe | Synchronous ordered source observation extraction and encrypted outbox insertion |

Unlike Android #3036, iOS observation is **inside** commit: observer/outbox
failure rolls back the canonical write. Ownership, apply and observe are
children of commit; summing them with commit double counts. The commit
residual includes admission, generation validation, precommit UI work and
finalization, not just lock wait or fsync. Successful observation alone does
not prove a committed change if a later precommit/COMMIT step fails.

No-op replacements omit observation. Existing iOS low-level empty-sequence
deletion semantics are preserved, rather than copying Android's empty-import
early return. Rejected/empty Store content emits only total and no claim of a
database commit. Direct DB callers are disabled by default; they may inject a
single timing instance across prepare/commit, and own their outer total and
scratch lifetime. Production checked Store entry points create a fresh timing
instance per source replacement, including the count-only attachment route.
Total is not embedding/index completion or an entire multi-attachment batch.

## Privacy and diagnostic failure isolation

Each replacement gets a random correlation UUID, hashed by the existing
tracer. Each phase invocation has a separate opaque span ID. No source, item
ID, path, content, title, model prompt or error text is accepted by the timing
wrapper. Storage correlation is not an Agent task-to-storage distributed trace.
There is no per-record timing: a normal changed replacement emits fourteen
boundary points regardless of source size.

Production source spans defer journal I/O to the existing utility queue. The
new opaque deferred path admits at most 256 pending points, dropping excess
diagnostics without waiting, retrying business work or modifying its result.
Already existing unrelated journal routes are unchanged. Journal event/file
retention remains bounded by the existing journal policy, not memory storage
capacity. Queue pressure, crashes or retention can lose boundaries; a retained
start without a finish is incomplete, never a successful sample. Entirely
dropped spans cannot be counted. Summary reads do not flush asynchronous I/O.
Failures/cancellations are unsuccessful and excluded from success percentiles;
the original thrown error is rethrown. Journal file failures are swallowed by
the existing local-only journal, without retrying a source write.

## Verification boundaries

Fourteen synthetic XCTest methods are authored for successful nesting and
privacy, fresh correlation, producer/preparation/ownership/revision failures,
apply cancellation, precommit failure, observation-outbox rollback, no-op and
empty deletion, broken journal, disabled timing and missing finishes. They
exercise the DB replacement path with a synchronous injected local tracer;
production tracing uses the deferred path. Source guards check production
Store routing and bounded deferred admission. These are not device throughput
or queue-pressure measurements.

Only JavaScript source/project checks are run in this Windows task. Swift
compilation, XCTest execution, real-device installation, native inference and
performance/capacity acceptance remain unverified. No Android timing numbers
are presented as iOS measurements. No reports or private evidence are uploaded.

The expanded static sweep also finds six pre-existing historical whole-file
scope failures in connector observation timing, image reply policy, image
search fusion/source adapters, model round timing and planning context timing.
Each reproduces against the unchanged pre-increment source. These unrelated
guards are not weakened or counted as passes by this increment.

Inherited limits remain: full UI arrays, long final writer/observation work,
legacy bulk mutation behavior, no automatic global-runtime outbox consumer,
no Store multiwriter cache reconciliation, no physical payload read lease and
no key-rotation/rollback recovery guarantee. This does not deliver canonical
partitioning, a universal latency bound or hundred-million-record acceptance.
