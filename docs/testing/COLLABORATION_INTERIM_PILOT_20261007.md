# Interim publication in adaptive pilot trials

This is test infrastructure for the generic collaboration runtime. No task
answers, private protocols, raw model results, provider defaults, UI changes,
or production version changes are included.

## Corrected gap

The adaptive real-model pilot constructed its own encrypted execution store.
After interim dispatch became an optional store capability, that constructor
still omitted the milestone workspace. Thus a trial could expose the publication
tool without exercising publication-triggered coordination. The pilot and the
synthetic device scenario now use the same test-only store factory, with the
production workspace and durable pause/stop control enabled.

## Preserve evidence before cleanup

The observer archive captures all milestone pages for the exact isolated
group/run/turn and current round. Earlier captured rounds are retained. Each
entry preserves the immutable published originals and only their explicitly
recorded tool observations. Source identities and hashes are checked; a missing
original, incorrect attribution or unavailable observation fails the capture.

Collection uses read-only APIs. It does not register model read coverage, publish
new evidence, modify a method, or communicate with any model. The report labels
the reader as `test_observer_not_agent`; `peer_read_proven` and
`scientific_acceptance_proven` remain false.

Successful report persistence precedes deletion of the synthetic conversation
and execution database. A failed capture keeps that trial state available for
investigation and cannot pass the integration verdict. Cleanup still stops only
the trial's own remote work. An empty archive is a valid null observation, not
proof that early collaboration happened.

## Verification

The focused local selection passed 52 tests with zero failures/errors/skips.
The broader collaboration/subagent/live-graph selection passed 1,245 tests in
101 suites, also without failures/errors/skips. Repository checks and six core
regression contract tests passed.
Six S26U instrumentation tests passed, including the shared pilot-store factory,
publication while the original worker is running, missed wake recovery, exact
version archive reads and repeat-capture deduplication. The device retained
Android 1.4.86 (1171); only the instrumentation package changed.

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests '*CollaborationAdaptivePilot*Test' --tests '*CollaborationMilestone*Test' :app:assembleDebugAndroidTest -x :app:buildNativeMemory --console=plain
adb -s $env:S26U_SERIAL shell am instrument -w -r -e class 'com.galaxyssi.chat.CollaborationMilestoneDeviceTest,com.galaxyssi.chat.CollaborationLiveGraphDeviceTest#liveReviewStartsBeforeUnrelatedMemberAndFinalWaits' com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner
```

No real model invocation or live MQTT publication was performed for this change.
The next authorized trial must separately inspect actual tool use and downstream
actions. A passing fixture or a saved original is not evidence of autonomous
innovation, retained learning, transfer, or superiority over a single agent.
