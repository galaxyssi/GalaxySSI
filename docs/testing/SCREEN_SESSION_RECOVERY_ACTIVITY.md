# Screen session recovery and message activity

## Regression

An old screen-analysis conversation could move to the top of the conversation list
without a new capture or reply. Restoring the selected model rewrote conversation
`updatedAt` with the wall clock. An interrupted local multi-Agent team could also
be treated as a stranded connector request and redispatched with a new team ID.

## Behaviour

- List activity is the latest indexed dialogue timestamp, not a model-setting or
  recovery timestamp. Legacy, unindexed conversations keep their existing fallback.
- Repeating unchanged metadata writes does not emit a conversation mutation.
- Enriching an existing final answer preserves its original completion timestamp.
- Team recovery reconciles the original team before liveness/model recovery.
- A live team is left running; a saved terminal result uses the existing response
  validation path. Missing, interrupted, or identity-mismatched teams pause without
  creating a replacement team or automatically replaying side effects.
- The paused parent can accept a late outcome for its original source ID, with the
  existing contact/conversation/turn checks still required. The pause notice does
  not overwrite the saved answer.
- A disabled screen assistant does not retry a pending capture.

## Automated checks

Run from `apps/android`:

```powershell
.\gradlew.bat :app:testDebugUnitTest `
  --tests 'com.galaxyssi.chat.ConversationHubModelsTest' `
  --tests 'com.galaxyssi.chat.AgentRecoveryTranscriptTest' `
  --tests 'com.galaxyssi.chat.AgentLongTaskRecoveryPolicyTest' `
  --tests 'com.galaxyssi.chat.AgentTeamParentRecoveryPolicyTest' `
  :app:assembleDebug :app:assembleDebugAndroidTest -x :app:buildNativeMemory
```

The native-memory build exclusion reuses the local prebuilt library; it does not
disable the runtime bundle checks. Unit cases cover list timestamps, original-team
reconciliation, active/terminal recovery exclusions, and late-result identity.
`AgentTranscriptProjectionInstrumentedTest` additionally covers repeated model
writes, final-answer enrichment, and preserving answers when a team pauses. Tests
create private, isolated conversations and delete only their own fixtures.

## S26U acceptance

Local validation on 2026-09-27: the debug app and instrumentation APK compiled;
105 focused JVM tests passed across nine suites (including task identity,
connector background identity/handoff recovery, team-plan bridging and list
status). `git diff --check` passed. The full-repository i18n checker reports
existing unrelated violations; this change keeps its new Chinese UI text in the
localized resource file.

The pre-fix screenshot showed an old answer and an active multi-Agent coordinator
timer. The screen assistant was disabled and the last capture file predated the
recurring recovery events. These observations do not establish a new capture.

Post-fix device acceptance remains pending if S26U is unavailable. Verify:

1. The old unavailable team settles to paused without a new team dispatch.
2. Reopening/backgrounding the app does not advance the list time or erase answers.
3. A new, explicitly requested screen analysis still produces a normal result.
4. A matching late team result can finish the paused parent; unrelated results do
   not attach to it.

The opt-in `inspectLiveScreenTaskMetadataOnly` instrumentation method can log IDs,
timestamps and phase metadata for one specified conversation. It is skipped by
default and does not export message text, screenshots, credentials or keys.
