# Android final reply UI latency

## Scope

Android 1.0.7 (853), based on main `488b37165` including PR #2810.
No Desktop, iOS, MQTT protocol, model routing, ASR/QNN, encryption-key,
checkpoint durability, or final-answer verification policy changes.

## Observed failure

A real Chinese question sent from S26U through Codex completed on Desktop,
but the phone did not promptly display the final answer. New same-process
monotonic stages located the delay; phone and Desktop wall clocks were not
subtracted from each other.

The instrumented, unfixed request at 19:17 on 2026-09-05 recorded:

| Stage | Milliseconds |
| --- | ---: |
| Final arrival to response consumer | 4,335.9 |
| Accept final response | 979.1 |
| Finalization | 4,427.0 |
| Durable checkpoint | 44.7 |
| Checkpoint to UI callback | 11,605.3 |
| UI callback to transcript submission | 3.2 |
| Transcript executor queue | 21.6 |
| Transcript persistence | 15.5 |
| Persistence to visible draw | 27.8 |
| Final arrival to visible draw | 21,460.2 |

Desktop execution was independently measured as 11,503 ms. The phone's
send-start to final visible draw was 46,288.5 ms. These are one request's
measurements, not P95 estimates or network guarantees.

An opt-in real-provider main-thread sampler reproduced the problem, with
heartbeat queue delay reaching 16,329 ms. Repeated samples identified:

```text
RecyclerView.onBindViewHolder
  -> agentProcessTranscriptRow
  -> VoiceAgentRunBridge.findByTaskId
  -> AgentRunEventVoiceAgentRunRepository.list
  -> decodeRun -> AgentRunEventStore.events
  -> AgentStorageCipher.decrypt -> Android Keystore Binder
```

Binding a progress row searched up to 256 historical runs and decrypted
their events, even for an ordinary non-voice request without a voice run.

## Fix

- Voice run updates and background restoration already prepare execution
  presentations. They now include an identity-only `AgentVoiceRunReference`.
- Row binding reads this existing presentation, not the event repository.
- Status refreshes preserve the reference; terminal state still disables
  cancellation. No new cache of message bodies or full voice snapshots is added.
- Cancel/detail clicks resolve the referenced run on the transcript executor.
  Run, conversation (including explicit merges), turn, and task identities
  are checked before the existing action runs. Missing/deleted records do not
  fall back to a different task.
- Persistent run events, key handling, and final-save-before-stream-retirement
  remain unchanged.
- Final-message ingress also called `consumeLegacyFinal` on the UI thread.
  It now publishes the canonical response first and updates that optional voice
  projection on the existing recovery executor. Projection failure cannot undo
  an already delivered reply. No voice features are disabled.

## Timing correctness

Final transcript rows use the mobile runtime ID while received frames use
the remote task ID. `AgentReplyTraceBindings` correlates those IDs only for
the exact conversation + turn + runtime tuple. This is diagnostic correlation,
not task reassignment or routing. A bounded diagnostic eviction cannot remove
business data. Cross-process clock domains are never joined.

The new stages cover final consumption, acceptance, finalization, checkpoint,
UI dispatch, transcript executor, persistence, and actual visible draw.
Only a task with a received final frame can emit these reply stages. The
existing outcome checks exclude failed/cancelled responses from success SLOs.

## Reproduction

The optional `AgentReplyUiQueueProbeTest` lives only in the test APK and is
skipped unless `live_reply_probe=true` is explicitly supplied. It sends one
Chinese question using the user's current model settings. It requires a
configured real provider and may consume provider quota. It logs thread
frames and diagnostic identifiers, not message text or credentials.

```text
adb -s <S26U> shell am instrument -w -r \
  -e class com.galaxyssi.chat.AgentReplyUiQueueProbeTest \
  -e live_reply_probe true \
  com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner
adb -s <S26U> logcat -d -s ReplyUiQueueProbe:I '*:S'
```

The 120-second wait is a test timeout, not an Agent action/time budget.
If the test times out, inspect the named conversation before retrying; the
test does not silently resubmit or cancel a user's task.

## Verification status

Instrumentation-only build: 29 JVM tests and three S26U journal tests passed.
The unfixed real Codex probe completed and reproduced the UI stall.
Final build: 59 JVM tests, six S26U device regressions, and the opt-in real
Codex probe passed. Repository checks and `git diff --check` passed.

Device regressions prohibit history lookups during repeated progress-row
binding, check cancellation identity/status presentation, and verify final
delivery precedes a voice history lookup on a non-main thread. They do not
send a real cancellation command to a user's task.

Real-device measurements, retaining the same installed app data:

| Measurement | Instrumented baseline | Row fix only | Final two-site fix |
| --- | ---: | ---: | ---: |
| Send start to final visible (ms) | 46,288.5 | 32,237.1 | 37,641.4 |
| Final arrival to visible (ms) | 21,460.2 | 12,159.8 | 13,775.8 |
| Final UI callback queue (ms) | 11,605.3 | 0.315 | 0.646 |

The final probe's first visible output was 22,941.8 ms; Desktop independently
reported Codex completed in 14,529 ms. Final transcript persistence was
12.27 ms. No main-thread heartbeat delay of at least 250 ms was sampled in
the final probe, versus repeated ledger-decryption stacks before the fix.
This sampled observation does not prove every frame is below 100 ms.

The final build was installed with `adb install -r`, version 1.0.7/code 853.
Its APK SHA-256 is
`bea7c36bfc58531ffac20bf4866efac24cc5a746b342a2339bdec934d1cde885`.
The original first-install time, pairings, models, and conversation data were
preserved. Only S26U (`SM-S9480`) was operated; the connected tablet was not.

Remaining measured costs include response-consumer waiting (8,046.0 ms)
and finalization (4,556.6 ms). The voice lookup still scans the repository
in the background and can delay other recovery work; replacing that lookup
with an indexed projection is follow-up work, not claimed as fixed here.
The UI fix does not claim to solve all end-to-end latency, general voice
repository indexing, every main-thread storage call, or provider variability.
The full-reply 10-second target and statistical P95/P99 gates remain open.
