# Native memory source replay

`galaxyssi-memory-native` **0.3.0** adds a transactional replay consumer to the
encrypted SQLite/DiskANN candidate. It does **not** activate native recall in the
Android App. At that stage Android used its existing JVM retrieval path. No APK or
Desktop version is changed by this native-library-only revision.

For the subsequent 0.4.0 JNI integration, see
[Android native activation](android-native-memory-activation.md); the evidence
below remains specific to the 0.3.0 native replay stage.

## Transaction and source contract

- One persisted epoch identifies a replay stream. Each event names its sequence,
  predecessor, opaque source key, revision, vector count and removal status.
  Sequence gaps are permitted only when the explicit predecessor matches the
  last completed event; an unfinished event must be resumed or invalidated first.
- Each append contains 1-64 contiguous vectors, not the full corpus. Graph nodes,
  neighbor edits, source provenance, document visibility and replay cursor commit
  in the same attached-database transaction. A failed write or cancelled session
  cannot publish a cursor ahead of its graph.
- A document is invisible until its final vector page commits. Replacement or
  removal hides the previous publication while retaining graph traversal nodes.
  Both source revision and event sequence must match: removing and re-adding the
  same content must not resurrect older vectors with the same content hash.
- Completed page retries do not insert more nodes. An overlapping partial page
  or missing page is rejected. Changed retries for the latest completed event
  are rejected. Older completed events are no-ops, not a retained event history.
- `skip` invalidates obsolete ready work when the authoritative source no longer
  matches it. The caller must verify that condition. This module does not read
  the Android source ledger or decide source permissions.
- A search holds a stable read transaction, filters incomplete/deleted/replaced
  candidates and returns source key, revision, publication sequence, chunk
  ordinal and offsets. Authentication failures abort the result rather than
  returning a partial list. The future App bridge must validate the source again
  before releasing text to an Agent.

## Storage and lifecycle

`index_records` stores the cursor, document publication state and per-node
provenance in the catalog. Values use AES-256-GCM bound to the database identity,
instance, opaque record key and transaction generation. Keys are not encrypted:
callers must supply opaque, appropriately namespaced identifiers, not source text.
Fixed binary records replace any whole-corpus JSON representation. The 1,024-byte
record bound and 64-vector append bound are per-operation limits, not memory-count
limits. Native retrieval still has bounded candidate/top-k scratch storage.

The caller owns the store and cancellation token and must serialize top-level
operations. The store rejects overlapping leases. No JNI handles, Keystore key
wrapping, background scheduler or Android lifecycle owner are introduced here.

Experimental stores created by version 0.2.0 lack `index_records`; replay attach
fails explicitly instead of creating an empty checkpoint over an existing graph.
They must be rebuilt as derived indexes from authoritative source data. Existing
Android memory databases are unrelated and must not be removed. Authenticated
encryption does not by itself prevent complete file rollback by a privileged
attacker. Source metadata sharding and physical tombstone reclamation remain
unfinished; heavy deletion may reduce bounded ANN recall until a rebuild.

## Verification scope

Run `tools/dev/test-memory-native.ps1 -Mode sqlite-android` on **SM-T575** for:

- Partial-page reopen, repeated page delivery, ordered predecessor validation,
  incomplete-document filtering and replacement/removal/re-addition.
- Provenance insertion failure after graph writes, with graph and cursor rollback.
- Wrong epoch, changed latest retry, missing pages, cancellation, invalid record
  bounds and authenticated-record substitution/corruption.
- Actual child-process exit without destructors after a committed page, followed
  by resume without duplicate insertion. The ignored child helper is invoked by
  the process-exit tests rather than run independently.
- Existing physical-shard, snapshot, transaction, process-death and bounded-cache
  regressions. Fixtures are synthetic and isolated under `/data/local/tmp`.

Run `-Mode host` for the unchanged generic-store adapter and probe regressions;
Linux CI runs all native features. App data, pairing, ASR/QNN and model files are
not accessed by these executables. These tests do not establish 100M-row capacity,
production semantic quality, whole-process zeroization or a 200ms App SLA.

### Recorded device result (2026-09-11)

On SM-T575, the final release ARM64 executable passed **19 tests**, with zero
failures and one intentionally ignored child-process helper, in **29.63s**.
All four ELF LOAD segments passed the 16KiB layout check. The executable SHA-256
is `f36489b7bad895ced850efeb4445f330db796b47c71c1298e79cf5eb72ee197d`.

The same-revision re-add test first reproduced two hits instead of one. Binding
provenance to the publication sequence as well as the content revision fixed it;
the unchanged test then passed. Raw synthetic evidence is retained locally:

```text
build/memory-native-evidence/e0854bb8bb9b48ed8ac1eac2fdad4afe/  # reproduced duplicate
build/memory-native-evidence/8a8ced990b1f484ca80fd6159432ab38/  # final 19-test pass
```

The Windows core-adapter regression passed **10 tests** in **7.99s**, including
32 held-out synthetic queries matching all 256 expected top-eight results.
This does not include SQLite on Windows; SQLite was exercised on Android.
Host evidence: `build/memory-native-evidence/2ac211d8f1c7488b87f960fdbd2461b5/`.

## Remaining activation work

Connect the durable Android vector feed to this consumer, wrap the index key in
Keystore, provide bounded JNI ownership, reconcile source/index generations and
validate source revisions before text retrieval. Follow with real semantic recall,
deletion residue, larger-scale cold/warm RSS and latency acceptance. The Run
Kernel, tracing and ordinary Agent DAG goals remain separate unfinished work.
