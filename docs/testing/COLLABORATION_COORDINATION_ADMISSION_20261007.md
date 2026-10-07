# Bounded coordination admission

Android 1.4.88 / 1173. No Desktop, model-selection, UI, or permission change.

## Failure mode

An incremental coordinator may be persisted after a researcher publishes an
interim milestone while all worker slots remain occupied. The ordered queue used
to hold its mutex while waiting for a permit. A queued worker could therefore
block updates to the whole graph, before the coordinator even emitted its queued
event. Sharing only worker capacity also left coordination waiting for long-lived
workers to finish.

## Contract

- Ordered admission reserves its next request under the queue mutex, then waits
  for execution capacity outside that mutex. Cancellation releases the request
  gate and does not leak a permit.
- The generic runtime keeps the original shared budget by default. An explicit
  coordination budget enables a second bounded pool, shared across that runtime's
  runs, not multiplied by the number of teams.
- Research team execution configures one coordination slot in addition to its
  configured worker slots. Only host-created live-planning checkpoints use it.
  Review, implementation, and final-delivery tasks stay in the worker pool.
- Resource context discloses worker, coordination, and total configured capacity.
  Existing outer dispatch, provider, permission, and cancellation controls still
  apply. This is not unlimited concurrency or a grant of new resources.
  It does not reserve a downstream Desktop/provider slot; a saturated remote
  executor can still queue the request. End-to-end load behavior needs separate
  real-provider acceptance.
- Permit suspension and reacquisition stay in the same lane. Lane identity
  survives append-only graph normalization and is reconstructed from durable team
  definitions. Event provenance records the assigned lane.
- Ordinary work remains ordered within its lane; execution is not preempted.
  Peer checks may still wait for worker capacity. The coordination lane lets the
  team plan while work continues; it does not guarantee immediate peer execution.

## Verification

- 1,348 selected unit tests in 111 suites passed with zero failures or errors.
- Debug APK and instrumentation APK built successfully from the final source.
- S26U (SM-S9480) was updated in place to 1.4.88 / 1173; application data was not
  cleared. All nine tests in `CollaborationMilestoneDeviceTest` and
  `CollaborationAdmissionOrderDeviceTest` passed on the final APK.
- Repository guard, Kotlin source-size policy, and `git diff --check` passed.
- No original user research, contacts, door controls, or other devices were used.

Final debug APK SHA-256:
`9e13fe6b2b2d15cb6c1a797258597a7d071361f6b812274996b6bb209e52772e`.

Reproduction:

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests '*Collaboration*Test' --tests '*AgentTeam*Test' --tests '*AgentSubagent*Test' --tests '*LocalModelWebToolAdapterTest' :app:assembleDebug :app:assembleDebugAndroidTest '-Pgalaxyssi.requireEmbeddedRuntime=false' -x :app:buildNativeMemory --max-workers=2 --console=plain
adb -s <authorized-device> shell am instrument -w -r -e class 'com.galaxyssi.chat.CollaborationMilestoneDeviceTest,com.galaxyssi.chat.CollaborationAdmissionOrderDeviceTest' com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner
```

New coverage includes two saturated workers plus queued work, live milestone
coordination, shared per-runtime budgets across teams, zero additional capacity,
queue update under saturation, cancellation during permit suspension, lane-local
reacquisition, explicit resource totals, and durable graph reprojection.

No real-model post-fix acceptance or scientific capability gain is claimed by
these local synthetic tests. Private paper material and trial data are not part
of this change.
