# Collaboration Evidence Inbox Recovery

## Failure and Boundary

The real candidate run `live-candidates-d2afc8bc-a27f-42f9-8978-cb4c908f3c53`
timed out after its Codex planner had already completed. Desktop accepted and
answered the phone's read-only `agent_task_evidence_request` queries. The phone
log at 03:06:05 and 03:06:34 on 2026-10-03 recorded:

```
Signal receive transaction rolled back: CapacityExceeded
```

The old inbox counted completed replay tombstones against the same record quota
as pending work. Once that quota was full, completing more work freed payload
bytes but did not free a record slot. Repeating a query or republishing a model
result could not repair the receiver's accounting. This is not evidence of a
public MQTT broker outage or of the model still running.

## Change

- Introduce transactional `pending_count` accounting for the global and per-pair
  inbox limits. Existing record and byte limits still apply to pending work.
- Backfill the pending count once from durable records when upgrading. Do not
  delete messages, Signal sessions, pairing information or replay proofs.
- Completion releases the pending record slot and payload bytes atomically with
  body compaction. Duplicate completion is a no-op; rollback restores the slot.
- Completed tombstones retain the existing eight-day deduplication window and
  expiry pruning. They no longer consume pending-work slots. Retained storage is
  time-bounded, not capped by the pending-record count; disk/storage failures are
  still errors, not success acknowledgements.
- Keep ciphertext alias limits, authenticated task/route bindings, evidence
  hashes, independent review and final acceptance checks unchanged.
- Capacity logs identify pending records, pending bytes or ciphertext aliases
  without logging message content or credentials.

The change does not bypass remote evidence import, rerun side effects, or declare
unverified candidate proposals accepted. It also does not remove Android's
background execution restrictions.

## Verification

`MqttAtomicInboxDeviceTest` covers migration, pending record/byte backpressure,
repeated completion, concurrent copies, transaction rollback, retained replay
proofs, expiry pruning, pair removal and a real Signal ratchet transaction.

`CollaborationEvidenceTransportDeviceTest` is explicitly opt-in. It reads an
already completed, authorized fixture through the production paired MQTT path
three times with fresh query nonces. It launches no model task and writes only a
content-free test report, including retained versus pending inbox counts and
query latency. Do not enable it for unrelated user tasks.

`CollaborationLiveCandidateDeviceTest` remains the separate real-provider
candidate/review/correction/recheck test. A passing transport test alone does not
establish scientific validity, full goal acceptance, model-format repair quality
or a multi-agent advantage over an equal-budget single agent.

Results are recorded below only after running the exact built APK.

## Results on 2026-10-03

- Android **1.4.25 (1110)** was built and installed on S26U without uninstalling.
  The existing Desktop process was preserved; no Desktop code change was needed.
- **708 JVM tests in 54 suites passed**, with no failures, errors or skips.
- **25 atomic inbox device tests passed in 1.956 seconds**, including the four
  new completion-capacity, migration, rollback and scoped-pruning cases.
- The first live read-only test saw 19,997 retained records and zero pending
  records/bytes on the affected pair. Two reads returned `ready` in 4.018 and
  6.433 seconds; the third timed out at 8.084 seconds. Desktop logged publish
  `rc=4` for that request. This sample is a failed test, not a pass.
- After the transient publication failure, a new read-only test started with
  **20,010 retained records and zero pending records/bytes**. All three fresh
  nonce-bound queries returned `ready` in **6.198, 3.459 and 3.147 seconds**;
  the device test passed in 15.947 seconds, with **zero model calls**. The empty
  index preserved `provider_history_complete=false`; it was not represented as
  proof of scientific or semantic correctness.
- The real candidate test is tracked separately below. Neither the earlier
  failure nor the transient read timeout is retroactively counted as a pass.

### Real Codex and DeepSeek Candidate Cycle

`live-candidates-402808ea-6eb4-48a4-97bb-d58d6c72a33e` passed on S26U in
**365.674 seconds**. It used the existing Desktop instance and real providers:

- Codex executed the single authorized read-only arithmetic command and the phone
  imported its original observation. Sum=15 and mean=3.75 were the observed values.
- Two independent DeepSeek reviews rejected the deliberate 16/4 negative control
  and supported the correct alternative. Each review retrieved and cited the
  original Desktop tool evidence, not just another member's summary.
- The editor corrected the rejected candidate to revision 2; the original
  revision 1 and the separate correct candidate were preserved byte-for-byte.
  Independent recheck supported the revised candidate.
- All four cloud publications succeeded on attempt 1. This does not exercise the
  separate malformed-publication correction loop against a real provider.
- Candidate work proceeded while the unrelated local test gate was blocked.
  Incremental planning, all candidate members and the final coordinator finished;
  every execution callback ran once. No manual result republish was used.
- Read-only evidence recovery encountered transient publication failures and
  retried without rerunning the successful command. No `CapacityExceeded`, fatal
  runtime exception or evidence-recovery exception appeared in this test process.
- `candidate_cycle_verified=true`, `original_evidence_count=1`,
  `stop_acknowledged=true`, and `retained_for_recovery=false`. Cleanup deliberately
  issued durable STOP and removed only the dedicated fixture. The saved report's
  post-cleanup state is `INTERRUPTED`; all actual dispatched member nodes had
  succeeded before cleanup. Three roster-only entries were correctly `SKIPPED`.
- Goal disposition remained `continue`, as required by this negative-control
  fixture: documentary review is not host semantic acceptance or scientific
  validation. No equal-budget single-agent comparison was performed.

The earlier 900-second candidate failure remains a failed sample. This single
successful retest demonstrates repaired completion/evidence transport and the
specified candidate workflow, not an overall reliability percentage or a p95.
