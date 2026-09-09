# Android semantic model lifecycle

Android 1.1.18 adds the user-facing lifecycle for the independent knowledge
encoder introduced in 1.1.15 and the encrypted vectors / hybrid search introduced
in 1.1.16-1.1.17. This does not replace the chat model or the ASR/QNN session.

## Model and activation

The knowledge page links to a localized **Semantic retrieval model** page with
download, cancel, import, enable/disable and update-index controls. Page data is
queried off the UI thread. The encoder is disabled until the user successfully
downloads or imports the pinned artifact; completion enables it automatically.
Disabling keeps the installed file and all knowledge records.

The independent encoder is BGE Small zh v1.5, GGUF Q8_0, 512-dimensional CLS/L2
embeddings and a 512-token context. Its CPU runtime is separate from all chat and
Whisper model instances. No model binary is included in the APK or Git repository.

Pinned artifact:

- Repository: `CompendiumLabs/bge-small-zh-v1.5-gguf`
- Revision: `5bf683e6a1bd454bbb60ba051088c50731d63fcb`
- File: `bge-small-zh-v1.5-q8_0.gguf`
- Bytes: `26472640` (25.25 MiB)
- SHA-256: `5a88d266870fbd27c6f329df60de80e2d4cf3bbd5e6f080bd5c1b2e5abb12039`

The primary HTTPS source is Hugging Face with a pinned-revision `hf-mirror.com`
fallback. Default OkHttp certificate verification is retained; downgrade redirects
are disabled. Source fallback does not relax the exact length or SHA-256 check.
The worker does not require Android's `VALIDATED` network classification, which
can reject usable regional networks when the system connectivity probe fails.
Actual HTTPS I/O determines reachability and uses WorkManager backoff on failure;
a fully downloaded artifact is verified and activated without a network request.
Transient I/O, HTTP 408/429 and server errors can retry. A final source rejection,
oversized response or checksum mismatch clears the active download request and
requires an explicit retry; application restart cannot revive that terminal error.

Files live in the App-private `files/knowledge-models/production/` directory.
Downloads use a sibling `.part` file, validate resumed Content-Range responses,
restart safely if the server ignores Range, fsync and atomically replace only a
verified model. Imports use a separate temporary file, so an invalid replacement
does not destroy an installed model. Cancellation keeps a resumable download but
cannot activate it. Request identities fence off stale worker completions.

## Persistent background indexing

Encrypted preferences persist model identity, enabled state and the active
download request. WorkManager persists download/index work across process death.
Startup and foreground recovery reconcile the enabled model with the durable
vector queue. Ordinary store writes schedule indexing after their transaction
commits; there is no special test-only retrieval path required for production.

Indexing uses the encrypted vector ledger's existing per-source/revision/ordinal
checkpoints. A batch commits at most eight chunks; a worker yields after roughly
15 seconds between batches and schedules a successor when work remains. This is
a scheduling quantum, not a lifetime action budget or a deadline on a document.
Foreground/source events coalesce to at most one pending successor while a worker
is running. An empty queue does not open the native encoder.

The controller owns one optional retrieval session per database instead of
loading a model per temporary store facade. Index workers close their independent
encoder on completion/cancellation. Query sessions retain the existing 30-second
TTL and privacy-boundary invalidation. Source revisions and access policy are
still revalidated when resolving ANN matches. FTS5 remains the fallback when the
model is disabled, unavailable, not indexed or exceeds the graph memory budget.

## Device acceptance (2026-09-09)

Verified on SM-T575 with Android app 1.1.18 (904). No existing user database,
pairing or installed model was reset. The production download was initiated from
the actual knowledge model page, not copied into the production directory by ADB.

| Check | Result |
| --- | --- |
| Focused JVM regression | 52 tests passed, including 9 verified-file tests |
| Lifecycle and hybrid device regression | 18 tests passed |
| Broader storage regression | 35 passed; one opt-in two-phase harness skipped |
| Real HTTPS download, hash verification and activation | 26,472,640 bytes in 26,432 ms |
| Real device reboot with pending indexing | 64/64 long Chinese documents completed; boot count advanced to 61 |
| Pre-reboot encrypted checkpoint | Exact ciphertext remained unchanged after recovery |
| Reboot verification duration | 228.105 seconds, including continued document indexing |
| Small-corpus hot hybrid query | 100 samples: P50 135 ms, P95 185 ms, P99 198 ms; 3/3 recall |
| Native APK alignment | 73/73 arm64 libraries passed 16 KiB checks |
| QNN package manifest | 24 libraries, 221.68 MiB, passed |
| Normal knowledge-page navigation | Model page displayed after startup, with no blank-value placeholder |

The download source selected by fallback was not recorded, so this evidence does
not attribute the successful transfer specifically to Hugging Face or its mirror.
The small-corpus query measurements are not a large-corpus performance gate.
Checkpoint preservation proves the saved row was not replaced; it does not count
every native inference invocation. Reboot continuation is not a claim of complete
Run Kernel recovery or a sub-five-second recovery target. Concurrent ASR/chat
latency remains a separate acceptance test.

The final debug APK SHA-256 is
`5c8075e192b7c0c23914b5f3801facc2aa4ae4f9f2008c59bd0e24262c5189f4`.
Local build evidence is retained under `build/semantic-model-*.log` (not committed).

### Reproduction

Build/install the debug app and instrumented APK without uninstalling the app.
Native lifecycle tests require the pinned model at the existing external test
fixture path `files/embedding-test/bge-small-zh-v1.5-q8_0.gguf` under the App's
external files directory. They use isolated database/model namespaces.

```text
adb -s <authorized-device> shell am instrument -w -e class com.galaxyssi.chat.KnowledgeModelLifecycleDeviceTest,com.galaxyssi.chat.KnowledgeHybridSearchDeviceTest,com.galaxyssi.chat.KnowledgeHybridNeuralDeviceTest com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner
```

The opt-in `KnowledgeModelProductionDeviceTest` accepts `knowledgeModelPhase`:
`download`, `prepare`, `verify` or `show`. It defaults to skipped. `download`
requires an absent production model and never deletes an existing one. `prepare`
creates named test documents and saves proof of a committed checkpoint; reboot
the authorized device before `verify`. Verification removes only its own named
fixtures and restores the preceding enable setting. `show` navigates through the
normal knowledge page and captures the model page after the startup overlay ends.
These phases deliberately exercise the real controller and WorkManager paths.

## Boundaries not claimed complete

- This is not a learned reranker. Retrieval still uses HNSW + keyed FTS5 + RRF.
- Disk-backed/sharded ANN and large-corpus cold-graph latency remain unfinished.
- The existing source-group UI limit and full-backup materialization are separate
  scalability work; the durable knowledge table itself no longer evicts at 500.
- Generic model catalog expansion and embedding-model migration are not included.
- This does not establish full Memory 2.0 or the complete nine-area product goal.
