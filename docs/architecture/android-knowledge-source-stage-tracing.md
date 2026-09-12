# Android knowledge replacement stage tracing

Android 1.1.110 adds timing to the production source replacement path. It does
not change the canonical schema, encryption, transaction boundaries, source
policy, synchronous observation, ASR/QNN or model lifecycle.

## Why this precedes further storage changes

The retained 10,001-body rewrite in PR #3035 took 333.044 seconds including
synchronous observation. That single total cannot identify the dominant cost.
Source preparation no longer owns the canonical writer, but the final apply
still does. Canonical storage remains one database; complete partitioning and
100-million-record acceptance are not delivered by this tracing change.

## Contract

The existing Agent runtime timing contract now includes seven phases prefixed
with `phone_runtime_knowledge_source_`, each with `_started` and `_finished`:

| Phase | Included work |
| --- | --- |
| total | Staging creation, all phases, semantic-index request and staging cleanup |
| stage | Consume the one-shot input, authenticate identity and persist encrypted staging |
| prepare | Open a committed read snapshot, authenticate old bodies, capture revision and stage old rows |
| commit | Writer admission, source revision check, ownership, apply, durable SQLite commit and maintenance scheduling |
| ownership | Recheck every incoming ID against current canonical source ownership |
| apply | Stream old/new staged pairs, normalize policy and update canonical rows and derived indexes |
| observe | Synchronous source mutation observation, including ordered visits |

`ownership` and `apply` are children of `commit`; they must not be added to it
when computing an end-to-end total. The commit residual includes admission,
revision validation and finalization; it is not a pure fsync or lock-wait metric.
An empty valid input only reports total and stage and does not claim a commit.

Each replacement has an independent random correlation ID, hashed through the
existing tracer. No record ID, source, path, title, content, error text or model
prompt enters these timing points. These standalone storage operation IDs are
not yet bound to an Agent task; they do not prove complete task-to-storage
distributed tracing.

Production events use the existing bounded asynchronous local timing journal
and existing P50/P95/P99 aggregation. Diagnostic retention does not cap stored
memories or actions. There is no per-record telemetry: a successful replacement
emits 14 boundary events whether it contains one record or a million records.
Missing finishes remain incomplete; failures, cancellation and timeouts do not
enter success percentiles. A failed observer leaves the already committed
write visible and reports failed observation/total, not failed apply. Telemetry
errors never retry the business operation, replace its exception or roll back
its committed state.

## Verification

The focused device tests exercise production replacement with a collecting
timing sink: complete success, input sequence failure, source ownership
rejection, post-commit observation failure, empty input and broken telemetry.
JVM tests cover every phase, independent/repeated correlation, timing failure,
exception identity, incomplete spans and disabled/unknown phases.

The retained full rewrite test uses the same production overload with a local
collecting sink for exact stage measurements. It changes every retained body
using an explicit variant, closes/reopens the database and verifies every ID
and body. It does not call an external model or export private memory.

The App and instrumentation APK built successfully, with 3,823 JVM cases
passing, five existing skips and no failures/errors. The 97-case device
regression selection passed in 179.937 seconds. All 74 AArch64 native libraries
passed 16 KiB alignment checks.

## Retained rewrite measurement

The same 10,001-body fixture was rewritten using variant `source-stage-v1` on
SM-T575. These are single-operation measurements, not population percentiles:

| Phase | Seconds |
| --- | ---: |
| Caller-observed replacement | 327.999 |
| Instrumented total | 327.982 |
| Input staging | 3.559 |
| Old-body preparation | 47.516 |
| Commit including its children | 243.306 |
| Ownership child | 44.556 |
| Apply child | 197.580 |
| Synchronous observation | 33.543 |

Reopen and verification of every ID/body took 73.125 seconds. The complete
retained test passed in 401.278 seconds, bringing this phase to 98 passing
device cases. The same fixture remains installed with the new bodies; its
post-test database SHA-256 is
`816e4e7dd1d352d5fa2544379f28e7215fbc4a1a219c6f4cd08e03a63fc1ba09`.
Raw bounded evidence is under
`evidence/knowledge-source-stage-tracing-20260912/`.

The test's callback executes the real source-observation extractor; it does
not enable the global Agent, enqueue global events or call a model. The default
production publisher can skip observation when global processing is disabled,
so this fixture total is not a universal end-user import latency.

The commit path dominates this case, with both ownership and application
holding writer admission. The measurements do not yet split Keystore/HMAC,
envelope crypto, FTS/trigger work and SQLite I/O inside application; attributing
the 197.580 seconds to one of those would be speculation. Future canonical
partition publication must reduce that work while preserving global ID
ownership, per-source atomic visibility, index revisions, policies, backup and
crash recovery. Merely opening more shard files does not satisfy those contracts.

The prior 333.044-second measurement used another content variant and cache
state. No controlled throughput improvement is claimed by this tracing-only
change. No universal 200 ms guarantee, completed canonical sharding or
100-million-record capacity is implied by these measurements.
