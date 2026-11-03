# Mobile artifact delivery and process clocks

## Failure evidence

The S26U investigation found three separate defects:

- Completed Desktop artifacts had already reached encrypted phone storage, but managed-team
  child results, persistence and parent delivery retained only text. Repeated generation could
  therefore produce more files without any visible attachment cards.
- Attachment/file requests without a command or explicit path could bypass the phone-owned
  reasoning loop. Selecting a remote reasoning provider then accidentally selected its host
  for execution too.
- The static FFmpeg build disabled dependency auto-detection without providing zlib. PNG
  encoding was absent. Copying the original JPEG after that failure did not satisfy an edit.
- Interim replies and paused/blocked workspace projections froze the process clock. A cached
  terminal timestamp survived a later recovery of the same task.

## Changes

- Preserve normalized rich output through adapter completion, child results, encrypted team
  persistence, late responses, snapshots and parent delivery. Only the successful primary
  member supplies the final rich output; observer artifacts are not automatically disclosed.
- Keep attachment/file reasoning in the phone-owned loop; propagate the supervised execution
  mode through team dispatch and enforce its planning boundary. Ordinary chat retains its
  existing fast route. No new phrase-matching rules are added.
- Let the model declare workspace-relative artifact requirements. Completion requires exported
  receipts; a transformation cannot be verified by an unchanged source hash. A changed hash
  is not semantic proof: the model must still inspect the requested edit. Files bundled in a
  ZIP must be exported individually when individual file evidence is requested.
- Render native runtime images as image previews, while other artifacts remain file cards.
- Derive elapsed time from the same-turn user message, prefer live task state over interim
  text, stop only for terminal workspace states, and invalidate stale terminal projections
  when recovery resumes.
- Link pinned zlib into FFmpeg, explicitly enable PNG, and require PNG/JPEG round-trip tests
  against the actual ARM64 binaries before packaging `8.1.2+png.1`.

## Regression commands

```powershell
cd apps/android
.\gradlew.bat :app:testDebugUnitTest --tests '*AgentCollaborationRuntimeTest' --tests '*AgentProcessClockPolicyTest' --tests '*AgentSystemToolPlannerTest' --tests '*AgentSupervisedProject*Test' --tests '*AgentTeamPlan*Test' --tests '*AgentSubagentRuntimeTest' --tests '*AgentCompletionRequirementsTest' --tests '*AgentArtifactCompletionEvidenceTest' --tests '*AgentRuntimeArtifactPresentationTest' --tests '*AgentPhone*Test'
.\gradlew.bat :app:assembleDebug :app:assembleDebugAndroidTest
adb -s <S26U-serial> shell am instrument -w -r -e class com.galaxyssi.chat.AgentProcessClockDeviceTest,com.galaxyssi.chat.AgentTeamArtifactDeliveryDeviceTest com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner
```

The artifact device test uses a unique encrypted database namespace and public generated image
and text fixtures. It checks rich-only results after reopening storage, then resolves the
received private image and file through content URIs and actually reads their bytes. It removes
only its own records/files. It does not contact a model or modify existing conversations.

## Deployment boundary

The FFmpeg fix is a runtime package change, not just an APK change. A host FFmpeg smoke pass is
not an ARM64 runtime pass. Rebuild, sign, publish and install the new runtime before claiming
the phone's existing FFmpeg binary has been repaired. See
[runtime packaging](../operations/android-runtime-packs.md).

Already completed historical team records which previously discarded rich output are not
automatically rewritten by this change. Do not mix artifacts from other tasks to reconstruct
such records. Full live-provider image-edit quality remains a separate end-to-end acceptance
check; hash and persistence tests do not prove the requested visual edit is correct.
