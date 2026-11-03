# Result readiness and background evidence archives

## Scope

Android 1.4.126 / code 1211 separates a returned collaboration result from the
completion of its entire remote execution archive. The previous live worker and
late-response recovery paths blocked on every pending archive record, including
unrelated tool outputs. Desktop source and model selection are unchanged.

The original full model result is now archived before either live suspension or
late-response deferral. Publication remains idempotent. Cancellation leaves the
original intact and does not mark the response applied or its workspace committed.

## Readiness rule

- Inspect the existing structured research-artifact envelope, including exact
  observation receipts nested in typed workspace bodies.
- Wait only if this dispatch has pending imports and a cited original is not
  available to the assignment through its existing evidence access.
- Release the result once these originals are present. Other imports continue
  through the existing durable, fair background importer.
- Malformed submissions or readable originals with a different digest go to the
  existing validator for precise rejection. Importing unrelated history cannot
  repair those errors.
- When imports end without supplying a reference, validation reports the missing
  evidence. A stopped, revoked or unsupported import is not a successful receipt.

Plain final Markdown, planner output and replies containing only already saved
milestones do not introduce unpublished observation dependencies. Their normal
planner, publication and goal-acceptance validation is unchanged. Model-authored
host metadata and JSON embedded inside prose do not create host dependencies.

The readiness check is not a verifier. It does not record model page reads, grant
access, change a source's origin, turn a simulation into an experiment, or accept
a goal. Publication still checks exact references and versions; independent
review, original-source coverage and computational qualification remain required
where applicable. Missing, corrupt or inaccessible evidence never becomes valid
because the wait has ended.

## Recovery and limitations

Both normal delivery and recovered successful replies use the same preservation
and reference-readiness policy. Failed replies are no longer delayed by unrelated
archive jobs. Existing pause/stop, identity, member isolation and dispatch ownership
checks remain in place. Background progress cannot revive a terminal member or
change its completion time.

The policy only knows explicit structured dependencies, not uncited evidence a
model should have supplied. This remains the responsibility of publication and
goal validation. Missing and inaccessible originals are intentionally not
distinguished by exposing another assignment's data. Such references may wait
while the corresponding import is still pending; existing pause/cancel remains
available. No new overall research timeout or retry count is introduced.

## Validation

Focused JVM tests cover reference availability, nested and duplicate receipts,
malformed output, wrong hashes, isolation, revocation, integrity failure, unchanged
read coverage, original retention before waiting, cancellation, late recovery,
idempotent publication and terminal-member presentation.

213 JVM tests passed with zero failures, errors or skips across 16 suites:

- AgentCollaborationRuntimeTest (26)
- CollaborationCandidateRuntimeIntegrationTest (5)
- CollaborationEvidenceLedgerTest (13)
- CollaborationEvidenceRecoverySchedulerTest (5)
- CollaborationEvolutionTest (22)
- CollaborationGoalAcceptanceTest (20)
- CollaborationLateEvidenceTest (9)
- CollaborationLiveEvidenceSyncTest (5)
- CollaborationNativeEvidenceTest (11)
- CollaborationPeerUpdatesTest (10)
- CollaborationPublicationRecoveryTest (13)
- CollaborationRemoteEvidenceTest (36)
- CollaborationResultEvidenceTest (12)
- CollaborationResultFinalizerTest (12)
- CollaborationResultReadinessRuntimeTest (1)
- CollaborationUnifiedStateTest (13)

The runtime integration test uses the real team scheduler with synthetic workers
and a pending archive. Independent work proceeds while an exact required original
is missing; the dependent member reads the saved full result immediately after
that original arrives, while the archive is still pending. This is a synthetic
scheduling result, not a real-model latency measurement or evidence of learning.

The final run compiled Kotlin and used the existing JVM options
`-x :app:buildNativeMemory -Pgalaxyssi.requireEmbeddedRuntime=false`.
Native packaging, APK installation and physical-device network/restart validation
are not claimed. Source-size and `git diff --check` also passed. This change is not
installed into an already frozen experiment. Initial test-fixture mistakes were
corrected to read full workspace originals and to test independent-reader coverage,
not the existing same-dispatch execution allowance; production review rules were
not relaxed.
