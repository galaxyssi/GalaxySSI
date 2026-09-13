# Native Attachment Receive And Compaction

## Failure Evidence

Two owned-loopback TLS runs reproduced the same failure after PNG, video and a
5 MiB file passed: the first window of the subsequent 21 MiB file never produced
the next attachment receipt. This happened **before** receiver restart injection.
The second run retained fresh endpoint snapshots and native error stacks:

- `build/mqtt-native-attachments-large-v1/report.json`: failure, no snapshots.
- `build/mqtt-native-attachments-large-v2/failure-snapshots.json`: one sender
  message still published, 37 receiver input chunks dispatched, no ingress
  admission rejections, and `Durable receive storage is full` in
  `signal_receive_handoff.persist_receive`.
- The per-peer 16 MiB receive-body quota counted every completed, locally sealed
  Base64 chunk body forever. File size alone was not the boundary: preceding
  transfers contributed to the cumulative quota.

This is a verified Desktop receive-storage defect, not evidence of a public
broker outage, Android rendering failure or a 21 MiB wire-packet limit.

## Fix And Invariants

Large receive bodies (at least 64 KiB in existing storage accounting) retire to
a small encrypted terminal proof only when all three conditions hold:

1. Business dispatch committed successfully, not merely MQTT/transport ACKed.
2. Every native Signal handoff for the body was acknowledged as released.
3. A durable ciphertext-to-message binding with its wire receipt hash exists.

The body deletion, terminal proof and quota adjustment commit in one SQLite
transaction. Original message/content hashes, ciphertext bindings, dispatch
attempt count and record quota remain. The proof includes only the bounded
envelope headers and fields needed for a duplicate ACK, never executable content.
Incomplete, retrying, running, uncertain or unbound messages keep their full body.
Deferred completed bodies are considered in bounded pages on later admission.

Exact ciphertext replays validate the saved proof, original endpoints, expiry,
delivery-attempt identity and unchanged wire binding, then repeat only an ACK.
An authenticated new ciphertext for the same unchanged message can complete its
native release without recreating the large body. Conflicting content is still
rejected. An already-enqueued recovery item recognizes a completed proof instead
of trying to read an intentionally retired body. Corrupt or misbound proofs fail
closed. Pair removal deletes its proofs and decrements the original shared quota.

No quota increase, TLS/Signal weakening, attachment compression change or local
attachment AES restoration is part of this fix. The existing encrypted transport
ledger still protects its metadata; artifact files retain the established policy.

## Verification

- Focused receive/dispatch/bridge selection: **69 passed**. Covers atomic quota
  rollback, deferred backlog, mutation and pair boundaries, pending native
  release, retired-body replay, stale queued recovery, unchanged-cipher header
  tampering, corruption and multiple completed chunks under a small test quota.
- Final expanded transport selection: **336 passed**, 24.355s. Includes the
  69-case focused selection; these are overlapping counts, not independent samples.
- Lab helper suites: **4 attachment**, **5 latency**, **4 fault**, and
  **8 measurement** tests passed in their appropriate isolated runtimes.
  A first attempt to discover all helpers in the endpoint environment failed
  because that environment intentionally lacks aMQTT. The controller tests were
  rerun with the owned-lab environment, not skipped.
- Desktop **37 checks** and structure check passed.
- The final native recovery smoke passed **20 business messages and three path
  cycles**, including delayed local-resume receipts, subscription loss after
  queue selection, native fragmented-envelope replay and process recovery.
  `build/mqtt-native-compaction-recovery/report.json` passed; both endpoint logs
  were empty. This is a separate correctness smoke, not artifact sample counts.

The first compaction native run failed on a stale internal recovery item after
the PNG body had been retired. This failure is retained at
`build/mqtt-native-attachments-compaction-v1`; it motivated the recovery guard,
not a relaxed acceptance criterion.

The following real native run passed (`build/mqtt-native-attachments-compaction-v2/report.json`):

| Fixture | Bytes | Result | Controller-observed completion |
| --- | ---: | --- | ---: |
| PNG, 200 x 170 | 102335 | Decode, SHA-256 and contact stream agree | 4.422s |
| H.264/AAC, 426 x 240, 2s | 71835 | ffprobe and full FFmpeg decode pass | 4.109s |
| File | 5242880 | 20 chunks, original SHA-256, one available attachment | 18.766s |
| File | 22020096 | 84 chunks, restart and path loss, original SHA-256 | 88.657s |

After the first 4 MiB of the 21 MiB case, the receiver process tree was killed
and recreated with the same identity/stores. One owned listener was stopped.
An already completed original chunk was replayed on remaining paths; its dispatch
count stayed one. Missing windows continued without resending all stored bytes.
There were no native ingress errors or cleanup errors in the final passing run.
The receiver's final **quota-accounted** size was 181631 bytes, with 106 compacted
records. This is not the SQLite database/WAL physical file size or phone PSS.

The independent repeat at `build/mqtt-native-attachments-compaction-v3/report.json`
also passed all five cases and cleanup, retaining the same restart/path-loss/
completed-chunk-replay checks. The PNG/video/5 MiB/21 MiB completion times were
3.797s / 4.735s / 22.329s / 120.344s. The added **32 MiB** case passed 128 chunks
over eight windows in 138.188s after the path loss. Its original and streamed
SHA-256 was `c539e9b0e61d579fab6bdb87ab460ca11cc9704ccef711e2fa8c15d9dc123dcc`.
Final quota accounting was 367384 bytes with 234 compacted records. Timing
variation is retained, not reduced to the fastest run; these are correctness
observations, not throughput or p95 claims.

## Scope And Remaining Gates

The test sends phone-shaped input manifests/chunks through two isolated Desktop
native Signal/MQTT endpoints. The receiver uses the real production attachment
consumer, transfer directory, contact store and attachment streaming API. Only
the test source's phone payload builder and business receipt consumer are fixtures.
It is **not** the Android/JNI sender: Desktop's classifier treats these input
chunks as ordinary messages, unlike Android's chunk traffic classification.
Consequently this does not prove Android adaptive striping or its performance.

Controller RPC, disk persistence, snapshot polling and injected restart are in
the reported completion times. No thirty-sample artifact performance gate, public
broker compatibility, Android screenshot, click/open/save UI, real model, ten
window, Doze, battery or App/App acceptance is inferred. Small completed bodies
and dedup proof retention still obey the existing bounded record budgets; this
change is not a comprehensive long-term inbox retention policy.

No production Desktop instance was replaced, no APK was rebuilt or installed in
this checkpoint, and no connected non-S26U phone was operated. Existing Android
1.2.0 (1005) build evidence remains from the prior checkpoint. The PR remains draft.

## Harness Isolation Correction

The native worker previously isolated data, configuration, database and native
Signal state but did not explicitly set `GALAXYSSI_WORKSPACE_ROOT`. Some owned
contact publication helpers can create task directories even without attachments.
Earlier blanket claims of no task-workspace writes are therefore too strong.
No conclusion about which historical directories were created is made here;
no directory in the user's default workspace was deleted.

The worker now sets and verifies the resolved workspace inside its disposable
endpoint root before transport startup. Received attachment paths must remain
inside that root. Test CA, identities and payload files stay disposable; only
synthetic hashes, bounded snapshots and test logs are retained as reports.
