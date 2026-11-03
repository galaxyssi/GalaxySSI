# Conversation Scheduled Tasks

## Scope

Android 1.5.30 (1313) adds a simple Scheduled Tasks entry to My Agents. The
management page lists the instruction, repeat time, next occurrence and paused
state. Its menu edits, pauses/resumes or deletes a schedule. The editor has two
fields: what to do and when. Deleting a schedule preserves the conversation.

Explicit recurring commands in a conversation create an editable task card.
Repeating the instruction in a conversation with one schedule updates that
schedule instead of adding a duplicate. An explicit new-task command creates a
separate schedule; ambiguous updates with several schedules show a picker.
Supported grammar includes minute/hour/day intervals, daily times, weekdays and
weekly times in Chinese, plus English intervals and daily clock times. Unsupported
natural-language expressions are not silently converted to approximate times.
Raw Cron editing and one-off reminders are not part of this UI.

## Execution Contract

- The persisted scheduler owns recurrence, not the model's reply text.
- Saving a conversation schedule makes its first occurrence due immediately.
  The existing durable occurrence path advances the next interval/calendar time
  and coalesces already-pending work. Restoring or resuming a schedule does not
  create an extra immediate run. Other proactive schedules keep their timing.
- Deterministic phone actions reuse the existing native planner and guarded
  executor before resolving a model. Explicit computer requests stay remote.
  Other occurrences resolve the originating conversation's current Agent/model.
  Selected model and reasoning parameters survive execution checkpoints.
- Explicit conversation schedules do not wait behind unrelated foreground-turn
  records. Phone authority and resource locks remain in effect.
- Remote completion requires an explicit outcome envelope, not merely a finished
  model response. Blocked/failed outcomes are failures; missing outcome/evidence
  is unverified. Model-reported evidence is not independent verification.
- Native app opening is verified with the existing foreground observer where
  available. Without that observer, or when Android blocks background launch,
  the result is unverified, never falsely completed. Clock configuration handoff
  alone does not prove that an alarm or timer was saved.
- The conversation card only shows the task name, repeat time and paused state.
  Tapping the entire card opens editing. Local observer/configuration diagnostics
  remain in run storage without creating repetitive chat replies or notifications;
  their known legacy transcript rows are hidden, not deleted. Real failures and
  useful model output are still delivered. Unverified is not promoted to success.
- Task cards and the manager update their status/next-occurrence labels on
  persisted state changes without polling or rebuilding the conversation.
- Desktop actions still require an available paired Desktop and its existing
  tool permissions. This feature does not launch the supplied Windows example
  on the developer's computer or grant additional tool permissions.
- Results and rich output are delivered to the original conversation. Identical
  result text, rich output and outcome status do not generate another message
  or notification. Changed wording can still produce a notification; this is
  deterministic duplicate suppression, not semantic equivalence detection.
- A pending occurrence coalesces later ticks instead of accumulating a backlog.
  A failed occurrence does not disable the repeating task. Pre-dispatch retries
  use existing backoff; after dispatch, recovery uses the durable execution ID
  instead of blindly repeating external effects.
- Pause disables future ticks and requests cancellation of active work. It cannot
  undo an external action that has already completed. Deleted conversation scopes
  disable their schedules.
- Completion, task counters and run state are committed together; delivery uses
  a stable deduplication key. Pending/undelivered records are not evicted as old
  completed history.
- The existing background-learning setting is unchanged. Schedules do not depend
  on world-model learning being enabled.

## Timing

An in-process coroutine timer supports short intervals while the process is
awake. AlarmManager is the persisted fallback; app startup and boot restoration
reattach schedules. There is no polling loop or new wake lock. Android sleep,
background-start restrictions, force-stop, network loss, and Desktop availability
can delay execution. A one-minute interval is not an exact Doze alarm guarantee.

## Validation

Initial 1.5.25 verification completed on 2026-10-16:

- 61 JVM tests passed across eight focused suites, with no failures or skips.
- `:app:assembleDebug` and `:app:compileDebugAndroidTestKotlin` passed.
- `node tools/dev/check-repo.js` and `git diff --check` passed.
- APK metadata matches source: 1.5.25 / 1308. Build used
  `-Pgalaxyssi.requireEmbeddedRuntime=false`; no runtime dependency download was
  required for this feature.
- APK SHA-256: `0CEC60546EF1300F33CA4BA84975B6ED53ADCD6F725281E239FF59EFAB7E7FE5`.

The focused JVM suite covers parsing (including spaced commands), time validation,
Cron next-occurrence calculation, result deduplication, model-context persistence,
management routing and existing team recovery/cancellation behavior. Repository
policy checks and APK/test-source compilation are run separately.

`ConversationScheduledTasksDeviceTest` contains fifteen isolated synthetic tests for
update identity, pause/resume, backlog coalescing, atomic/idempotent completion and
cross-conversation isolation, unrelated foreground work, unverified outcomes,
resume presentation, prior-revision status isolation, immediate first execution,
calendar timing after that immediate occurrence, compact cards, retained quiet
diagnostics, narrowly scoped legacy status filtering, and live card speech text.
They intercept service/activity starts and do not call a model or launch external
apps. Updated build and device results are recorded below after execution.

## 1.5.26 Regression Diagnosis

Read-only inspection of S26U and S20U confirmed that recurrence was registered.
S26U was repeatedly waiting on an unrelated persisted foreground workspace,
causing approximately one service wake per second. S20U dispatched a phone clock
instruction to its selected Desktop Agent; even a reply saying that no phone was
connected was recorded as completed. Both failure modes are covered by the new
execution admission and outcome handling.

1.5.26 passed 30 focused JVM tests and was installed on both S26U and S20U.
Android ActivityTaskManager observed actual local Clock activity launches:

- S26U: 17:02:36 and 17:03:36; target activity displayed after 195 ms and 90 ms.
- S20U: 17:02:55 and 17:03:55; target activity displayed after 289 ms and 263 ms.
- The paired Desktop retained the same eight prior schedule requests, with no
  new schedule dispatch during these local occurrences.
- Neither phone had the foreground accessibility observer enabled. The App
  correctly retained an unverified outcome; the above verification is from the
  external device test, not a claim that the App observed the target screen.

The initial device suite passed six tests but one failed in test-data cleanup
with ConcurrentModificationException. Its tracked fixture paths now use
concurrent sets; the failed run is not counted as a passed suite.
An intermediate nine-test run also exposed callbacks retaining handles to an
already-deleted fixture database. Fixture files are now removed by the device
harness only after instrumentation exits, not while callbacks still use them.

## 1.5.27 Status Presentation

Re-enabling a schedule previously displayed its last cancelled occurrence until
the next tick. Enabled schedules now show pending when that last occurrence was
cancelled/skipped or belongs to a prior task revision. Terminal outcomes are
labelled as the last run, not the current schedule. Existing persisted task cards
render frequency/status from live task data instead of an old paused label.

## 1.5.28 Immediate First Occurrence

The build and all 30 focused JVM tests passed. Both phones passed all 11 device
tests then present in the suite. S26U sent the test instruction at 17:24:01.367;
ActivityTaskManager recorded SHOW_ALARMS at 17:24:04.043 and the displayed Clock
activity at 17:24:04.225. The next occurrence ran at 17:25:04.289, displaying at
17:25:04.340. This confirms immediate first dispatch followed by the interval,
not a one-minute initial wait. The user subsequently edited that test schedule;
their edited task was left intact.

## Remaining Acceptance

Notification deep links and offline/Doze recovery still require dedicated real
device acceptance. The real Android-to-Desktop-to-model execution path has not
been claimed as accepted by the local build checks or native Clock observations.

## 1.5.29 Compact Presentation Acceptance

- Debug APK, instrumentation APK and all 30 focused JVM tests passed.
- S26U and S20U each passed all 14 isolated device tests with no failures.
- Both installed packages report 1.5.29 / 1312.
- S26U and S20U screenshots show compact clock/title/repeat-time cards, including
  historical cards. The local unverified diagnostic paragraphs are absent.
- Tapping the S26U card opened the existing editor with the correct instruction
  and repeat time; cancelling the editor did not change the schedule.
- User-paused schedules remained paused. No model, contact or door action was
  used by the synthetic suite. Fixture-prefixed files were removed only after
  both instrumentation processes exited; regular messages/settings were retained.
- Repository checks and `git diff --check` passed.

## 1.5.30 Speech Presentation

Compact schedule cards previously hid the saved/updated explanation visually,
but read-aloud still preferred the raw transcript text. Schedule speech now uses
the card title and compact repeat-time line, including paused state. Legacy text
blocks and diagnostic lines are excluded from both manual and continuous voice
speech. Manual read-aloud reads the already-rendered live status without querying
storage, so a paused or deleted task does not use an obsolete transcript status.
Ordinary replies retain their existing speech selection.

- Debug APK and instrumentation APK built successfully.
- All 60 focused JVM tests passed, including six new schedule speech tests.
- S20U reports 1.5.30 / 1313 and passed all 15 isolated device tests.
- The device speech test checks the current visible label after pause/delete
  presentation changes. This validates speech text, not an acoustic listening test.
- S26U disconnected before installation; this revision is not installed there.
- Repository checks and `git diff --check` passed.
