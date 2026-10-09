# Receiver-Driven Artifact Chunk Recovery

Android retains authenticated partial Desktop artifacts in its existing private
artifact store. Previously, exhausting transport retries could leave a valid
subset there indefinitely. A later manual request or connection recovery could
replay the whole file, but the receiver could not request its missing pieces.

## Behavior

- A background scan runs at most once per 15 seconds while MQTT is connected.
  It requests nothing until the exact paired route is ready. Existing agent-task
  identity must match; a revoked or different route cannot recover the file.
- Incomplete legacy MQTT artifacts reuse their existing manifest and chunks.
  After 10 seconds without a new chunk, the receiver requests at most eight
  missing indices. This is a transport window, not a research or task limit.
- The missing-index signature and next request time are persisted before I/O.
  Unchanged gaps back off through 30, 60, 120, 240 and 300 seconds. A changed gap
  starts a new window. There is no retry-count cutoff that discards partial data.
- Requests and automatic chunk responses are not added to another durable
  outbox. The persisted receiver gap is the retry authority. A scan admits at most
  eight artifacts, and older recovery records are considered first.
- Desktop restores only the original route-owned artifact, validates the task,
  source hash and indices, and seeks to the requested chunks. It retains the
  original conversation, turn, file identity, chunk count and full-file digest.
  It does not rerun the model or recreate the output.
- Completion still requires the ordinary full-file SHA-256 check and durable
  phone receipt. Successful storage removes the partial directory and therefore
  its recovery request state. Existing receipt replay remains in force.
- An unavailable source does not discard the partial file or raise a repeated
  manual-download UI error from the background scan. The receiver backs off.
  Explicit user-requested full-file downloads retain their existing error path.

The Blob relay protocol and its limits are unchanged. This increment cannot
recover a file when no chunk or manifest ever arrived, when the original source
is gone, or when no valid pairing/registered task identity exists. It does not
guarantee public broker availability or turn old failed experiments into success.

## Verification

Python coverage checks selective reads, original bytes/hash/count, wrong-task and
invalid-index rejection, owner binding, transient responses and unchanged manual
full-file behavior. Run from the Desktop backend directory:

```powershell
python -m unittest test_artifact_missing_chunks test_artifact_delivery
python -m unittest discover -p "test*artifact*.py"
```

`AgentDesktopArtifactRecoveryDeviceTest` uses isolated Android file roots and
preferences. Its cases cover a missing first chunk, original full-file bytes,
completion stopping further requests, offline/revoked routing, persisted pacing,
task mismatch and recovery of an existing uniquely registered partial file.
It does not send real MQTT messages. Run it with the existing
`AgentDesktopArtifactReceptionDeviceTest` and `AgentDesktopArtifactStoreTest`
to retain receipt-replay and storage regressions.

Real-network recovery must separately check the preexisting gap, requested
indices, phone-owned full-file bytes and Desktop stored receipt. Keep that audit
separate from any original task or experiment verdict.

## Verified on 2026-10-09

- Android 1.4.122 / 1207: debug and instrumentation APK builds passed. The JVM
  selection ran 152 tests: 151 passed, one skipped, no failures or errors.
- Desktop 1.4.44: artifact discovery ran 345 tests: 343 passed, two skipped.
  The 68 JavaScript/structure checks also passed. An earlier structure test hit
  its existing timeout during compilation; the unchanged test passed on rerun.
- S20U SM-G9880: all 13 recovery, receipt and storage instrumentation tests passed.
  Installation preserved app data; other phones and watches were not operated.
- Two preexisting partial files (534,189 and 6,822,086 bytes) subsequently reached
  the phone with exact original SHA-256 hashes and Desktop `stored` receipts.
  The larger file's persistent gap narrowed from nine missing chunks to two,
  then one, and completion; Desktop recorded six receiver-initiated requests.
  The normal reconnect/full-file replay also remained active, so this is a
  coexistence recovery check, not an isolated causal comparison of retransmitters.
- After the instrumentation process restart, both complete files remained
  readable and unchanged. This is not a phone reboot or prolonged Doze test.
  No model calls or original task re-execution were performed.

Main APK SHA-256:
`4d944b4d208631b53cc98a09632781f2a96d9817d30f02332b9d32f20bc89de2`.

No claim is made about bounded end-to-end public-network latency, entirely lost
offers, permanently unavailable source files, or historical failed outbox cleanup.
