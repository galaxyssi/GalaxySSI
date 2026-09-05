# Android provider attempt recovery

Android 1.0.10 extends the connector fallback work with structured cloud transport observations.
The default physical validation device is now SM-G9880 (S20 Ultra). The previously accepted
roughly 20-second reply target remains unchanged. Desktop and iOS code are not changed by this phase.

## Transport observations

`AgentProviderAttemptTracker` records the actual resource, provider, model, request ID, ordinal,
HTTP status, classified failure, retryability, and elapsed time for each call. It records only
started, connected, first output, completed, and failed transitions. Token updates do not write
additional checkpoints. Requested model overrides belong only to the initially selected contact;
an alternative contact resolves its own configured model.

`AgentProviderAttemptJournal` appends these transitions as a transport child Run in the existing
encrypted Run Kernel database. Each event contains one attempt, not the entire accumulated
history. Replay reads bounded event pages. Source message, conversation, turn, task, and action
jointly determine the child Run identity; its terminal state is not the parent goal's terminal
state. A failure to persist diagnostic events does not abort a healthy model stream.
The child carries `recovery_mode=observation_only`: the startup coordinator must not create
another workspace or dispatch a new task for it. Its owning dispatch restores the observations.

The journal contains no API keys, request headers, prompts, generated text, or raw provider error
bodies. Existing encrypted response storage still owns the user-visible content and error message.

## Fallback and recovery

- Do not pre-mark every configured cloud candidate as exhausted before making requests.
- Carry the completed report through ordinary and managed response persistence.
- Validate the complete response/action identity before applying its report to the runtime.
- Preserve structured error classes instead of reclassifying a localized error message.
- Merge actual inner attempts into the outer fallback trail. Inner retry exhaustion cannot be
  reset by a catalog refresh or the outer soft-retry queue.
- An interrupted second provider remains the current provider even when the first failed.
- The timeout path replays the pending dispatch's journal before considering alternatives.
- Manual target locks still prohibit switching to another contact.
- Stream updates use the same task ID as the final response, including when task and turn differ.

This phase does not restore a dead HTTP socket or automatically replay a request with uncertain
side effects. An unfinished attempt remains unfinished. Durable observations inform the existing
runtime timeout/fallback policy; full provider cancellation and acknowledgement recovery remain
separate Run Kernel work. A new user turn starts a new attempt scope.

## Validation

The focused JVM suite covers codecs, retry trail integration, identity isolation, current-model
recovery, localized error preservation, duplicate progress suppression, and existing kernel and
fallback contracts. Device tests use isolated test databases, not production contacts or API keys.

Device coverage includes encrypted inbox/journal reopen, idempotent append, a 281-event paginated
replay, structured cloud failure entering the real `MobileNativeAgent` fallback loop, and separate
instrumentation processes for save/recover. Faults are injected; these cases do not assert that a
real commercial provider returned a particular billing or timeout error.

Run the opt-in process phases separately, using a fresh `provider-process-<UUID>` token:

```text
adb -s <S20-serial> shell am instrument -w -r -e class com.galaxyssi.chat.AgentProviderAttemptDeviceTest#saveBeforeProcessDeath -e providerRecoveryId <token> com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner
adb -s <S20-serial> shell am force-stop com.galaxyssi.chat
adb -s <S20-serial> shell am instrument -w -r -e class com.galaxyssi.chat.AgentProviderAttemptDeviceTest#recoverAfterProcessDeath -e providerRecoveryId <token> com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner
```

Do not uninstall the production App, clear its storage, replace credentials, or re-pair devices
to run these tests. Only the temporary test databases are removed by the test code.

### Verified on 2026-09-06

- 73 focused JVM tests passed; repository checks and both APK builds passed.
- S20U: 15 ordinary device cases passed. The two new opt-in process phases passed separately,
  saving in PID 8432 and recovering in PID 8499. The older phase's opt-in process pair was not
  rerun; it remains excluded from this phase's 17 passed device-case count.
- One live Chinese Codex question completed and survived App reopen. Transcript timestamps
  recorded the first segment at 17.314 seconds and the final answer at 27.873 seconds after the
  user entry. This single result is not a P95 benchmark or a 20-second completion pass.
- Activity cold-start `TotalTime` was 1,401 ms, not a measurement of complete transcript loading.
- Crash buffer was empty after verification. Production first-install time was unchanged;
  only the separate instrumentation package was uninstalled at the end.
- Installed APK SHA-256: `29825fa9fb4a8cc4a7470f7e260bbe638cd56b0dc77eef0ef41864d174cddd4e`.
