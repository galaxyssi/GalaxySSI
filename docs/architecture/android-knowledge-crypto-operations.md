# Knowledge record crypto operations

## Scope

Canonical knowledge headers and inline chunks reuse `AgentRowStorageCipher`,
the existing Keystore-wrapped AES-256-GCM data-key implementation. Database,
opaque record ID, and part ordinal remain authenticated as associated data.
Each encryption gets a fresh nonce. Payload segments, native vector encryption,
ASR/QNN, and model lifecycle policies are unchanged.

Schema 13 rejects older clients before they encounter the new row envelope.
Legacy hardware-encrypted records remain readable without an eager corpus
rewrite; normal subsequent writes use the new envelope. Authentication failures
remain errors, not missing records or empty results. Existing foreground/background
key-cache clearing applies to the reused cipher; this change does not promise
immediate JVM-wide plaintext erasure or a new global key TTL.

## Index operations

Persistent index values use the exact existing Keystore HMAC, with explicit UTF-8
encoding and allocation-light hexadecimal encoding. A writer/access operation may
memoize 64 results. Lookup keys are keyed tokens from an operation-private random
key, not plaintext IDs or unkeyed input hashes. The memo is discarded on outermost
success or failure. Nested access shares that ownership; independent read snapshots
never borrow a writer's memo. This cache capacity does not limit stored memories.

Source replacement validates incoming ID ownership through authenticated source
metadata. The old source is still fully read and authenticated before mutation;
cross-source collisions still abort the transaction. Missing derived previews
fall back to authenticated canonical reads.

## Measurement and boundaries

The pre-change SM-T575 baseline is retained under
`evidence/knowledge-crypto-operations-20260912/baseline/`.
It measures 100 samples per operation. Hardware AES median was approximately
3.5 ms versus 0.2 ms for the existing wrapped-data-key cipher. Canonical writes
had a 42.2 ms median inside one transaction. Those samples are not durable
standalone-write latency measurements.

`tools/dev/test-knowledge-crypto-operations.ps1` requires the original synthetic
10,001-body fixture, rewrites it through normal source replacement, closes the
store, clears cached data keys, reopens, and checks every body and stable ID.
The fixture is retained. Other devices and production database names are rejected.
The separate source-streaming regression runner covers existing paging, identity,
backup, search snapshots, payloads, and rollback behavior.

SM-T575 results for Android 1.1.106 (992), September 12, 2026:

| Measurement | Baseline | Optimized |
| --- | ---: | ---: |
| Canonical header read, median / P95 | 3.95 / 6.58 ms | 0.50 / 0.69 ms |
| Canonical full read, median / P95 | 12.45 / 20.17 ms | 1.11 / 1.88 ms |
| Canonical write inside transaction, median / P95 | 42.22 / 52.24 ms | 17.07 / 30.52 ms |
| Retained 10,001-body replacement | 659.246 s | 433.278 s |
| Reopen and verify all 10,001 bodies | 232.684 s | 58.031 s |

Each microbenchmark has 100 samples. Canonical read samples repeatedly read one
record inside one database operation; canonical writes use distinct IDs with a
shared source and title inside one transaction. They are not random-corpus or
standalone durable-write benchmarks. The seven new device cases passed in
497.758 seconds. Both bulk runs replace 10,001 real encrypted bodies with an
overlapping ID range, but they are sequential mutations of the same retained
fixture, not byte-identical A/B replays. The optimized replacement still reads
legacy bodies; the reopen check reads newly written envelopes after key-cache
clearing. Different device conditions can affect hardware timings. Standalone
commit latency and steady-state production P95 remain separate measurements.

The full JVM run has 3,822 cases: 3,817 passed and five existing skips, with zero
failures or errors. Repository checks and 74-library AArch64 alignment passed.
The existing 106-case device suite also passed in 1,375.957 seconds, bringing
this phase to 113 passing device cases. Its fresh 10,001-body fixture measured
280.261 seconds to seed, 399.466 seconds to replace, and 57.850 seconds to reopen
and verify. A separate 1,201-body hot FTS corpus returned one matching body with
P50/P95/P99 of 19/28/30 ms over 100 samples. These corpus-specific results are
not 100-million-record or production UI latency acceptance.

This phase does not claim 100-million-record acceptance, bounded bulk transaction
duration, physical reboot recovery, or universal sub-200 ms retrieval and writes.
Canonical metadata is still in one WAL database; long source replacement still
owns one writer transaction. Full tracing, all-path Run Kernel integration, and
ordinary Agent Loop durable DAG acceptance remain separate active goal work.
