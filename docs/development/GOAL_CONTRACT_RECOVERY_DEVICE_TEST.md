# Goal Contract Process Recovery Fixture

Entry point:
`com.galaxyssi.chat.CollaborationGoalContractRecoveryDeviceTest#processCheckpointPhase`.
This is an opt-in, two-invocation Android instrumentation test, not two store
instances in one process. It does not start a model, execute a tool, contact a
provider, or control/terminate a device process itself.

## Parent-Driven Phases

1. Use a fresh lowercase 32-hex `goalContractToken` and run the method with
   `goalContractPhase=seed`. Keep the same app installation, private data and
   Keystore for recovery. A reused token with retained state is rejected.
2. End the seeded target process using the parent's approved test harness, then
   invoke the same method with the same token and `goalContractPhase=recover`.
   Recover asserts its PID differs from the encrypted marker's seed PID. A
   same-process retry fails without cleanup. Do not clear data or reinstall
   between phases. No Gradle/ADB invocation is performed by this slice.

Seed uses only `goal-contract-recovery-fixture-<token>` and its scoped encrypted
contract/ledger rows. The encrypted artifact database is
`test_goal_contract_recovery_artifacts_v1`, key `fixture:<token>`. The marker holds
phase progress, seed PID, descriptors, one prefix page, opaque resume cursors,
and verification hashes. Status output contains only fixture/phase/PID/count
metadata, never goal/context text or cursors. No public file is written.

The fixture binds both exact accesses in `CollaborationEvidenceLedger` **before**
contract publication/pinning. It requires the parent's exact-access
`authorizes(access)` implementation; it has no permissive/default-run-store
fallback. Production sources are not changed by this test slice.

## Assertions

- The intact snapshot preserves a 100k-character goal, oversized criteria,
  roster and previous assessment, including escaped/Unicode text and an empty
  optional section. Recover resumes the saved cursor, checks byte-identical page
  replay, and reconstructs the original goal, criteria, source IDs/text and
  contexts exactly, with bounded UTF-8 JSON pages and contiguous fragments.
- A separate pinned snapshot in the same fixture group has page 1 deliberately
  deleted during seed. Recovery must report `snapshot_corrupt`, expose no page
  content/cursor, preserve its pin, and neither repair nor republish the snapshot.
- Both pins remain unchanged; alternate-snapshot reads/rebinding, borrowed
  cursors, wrong round and altered dependencies fail closed. Scoped row hashes
  before/after recovery prove that reads did not rewrite contract or ledger rows.
- Direct fixture-row inspection checks the authenticated encrypted storage
  envelope and absence of plaintext sentinels/cursor in storage columns. This is
  an at-rest row check, not a claim about whole-device forensic erasure.
- Cursor reads produce zero delivery receipts and zero evidence observations.
  No call registers delivery, inline delivery, comprehension or acceptance.

All verification completes before cleanup. Successful recover removes only the
dedicated fixture group, contract/ledger rows and its artifact marker (last).
There is no `finally`/`@After` deletion: seed/recover failures retain the marker
and available fixture evidence for inspection. Do not reseed over a failed
fixture or clear shared production databases to reset it; use a fresh token.

## Recorded Parent Verification

On 2026-10-02, application and instrumentation APKs built, and Android
**1.4.20 (1105)** was installed on S26U without clearing data. Seed passed in
**1.562 seconds** with PID **16706**; recovery passed in **3.422 seconds** with
PID **16848**, reading the same **51-page** snapshot and then removing only its
fixture records. There was no reinstall or data clear between phases. Both
instrumentation invocations exited naturally; recovery asserted a different PID.

This is actual process-boundary storage recovery, not a device reboot, Doze,
network outage, model execution or proof of comprehension/semantic correctness.
