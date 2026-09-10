# Background Connector Recovery

## Incident

S26U dispatched an image review and then a second conversation. Desktop stored
different conversation, task, thread and turn identifiers. Both Codex runs later
stalled without model output. Android restored the second handoff with an empty
local outbox and no locally remembered remote status, modified its retry input,
and reused the original effect identity. The idempotency guard rejected it.
The later timeout reply was rendered through the orphan transcript path, rather
than continuing the original automatic fallback lifecycle.

## Changes

- Known Desktop handoffs use the existing authenticated recovery query and result
  inbox; an empty local outbox no longer authorizes a second remote task.
- Before the local not-accepted/not-running timer cancels a task, query the exact
  paired Desktop/source/conversation/turn. Confirmed queued/running work waits for
  the Desktop watchdog. Query failure is not fabricated as a remote status.
  Resolved timeout stages and tasks with no fallback skip this additional query;
  ordinary background recovery remains responsible for their result discovery.
  Authenticated status is checkpointed, and a resolved stage is not polled again.
- Explicit transport recovery gets a scoped, bounded handoff-attempt identity.
  Changed inputs within that attempt still fail the input hash check.
- Persist the actual dispatched connector parameters. Trusted handoff replay
  does not reroute or rematerialize the already dispatched action.
- Recover the specific legacy handoff-conflict failure only when the original
  durable receipt matches source, contact, conversation, turn and task. Reading
  the receipt never dispatches a tool. Cancellation, unrelated failures and
  exhausted budgets are not reopened.
- Late provider failures, like late successes, can rejoin a recoverable local
  timeout. Reopen only the retryable execution-loop phase, retaining budgets.
- A terminal recovery result is persisted as terminal, not submitted as a
  non-terminal recovery snapshot.

No chat UI, network credentials, pairing, Desktop binaries or permission
settings are changed. Model fallback still requires an available eligible
provider; this does not make a text-only model able to inspect an image.

PR version: Android 1.1.63 (949). The S26U runs below used the development
1.1.62 (948) build based on `c931af62d`. Main was subsequently refreshed to
`e9af6eea8`; its independent memory change also used 1.1.62, requiring this bump.

## Verification Matrix

Host regression suites:

- AgentConnectorHandoffRecoveryTest: primary/recovery/fallback receipt isolation,
  changed-input rejection, read-only scoped receipt lookup and ten parallel scopes.
- AgentActionEffectExecutorTest: duplicate and unknown effects, concurrency,
  fallback and immutable input checks.
- AgentConnectorFallbackActionTest / AgentConnectorFallbackTrailTest.
- AgentExecutionContinuityTest / AgentLateConnectorResponsePolicyTest.

Device suite: `AgentBackgroundConnectorRecoveryDeviceTest`:

- Ten simultaneous conversations dispatch, move to the Android home screen,
  recreate their runtimes from encrypted session checkpoints, receive independently
  injected Codex timeouts, fall back and complete with conversation-specific replies.
- Ninety cross-conversation response attempts are rejected.
- Duplicate old timeouts cannot disturb the newly selected provider.
- A legacy local action-ID conflict recovers its original receipt without sending
  again, then handles the real provider failure through fallback.
- Explicit transport recovery has a new replayable receipt.
- Cancelled work is not resurrected by a late result.

The device provider adapter is a deterministic test double. It exercises the real
Android Agent loop and encrypted persistence but is not evidence of ten successful
live Codex/DeepSeek requests or a real provider outage. Live MQTT/provider smoke
testing is a separate acceptance step.

Device target is S26U / SM-S9480 only. Do not run connectedAndroidTest without a
serial restriction when other devices are attached. Do not clear user app data.

## Verified Results

- Android 1.1.62 (948) installed over 1.1.59 (945) on S26U with `adb install -r`.
  User data and pairing were not cleared.
- 115 host tests passed across 11 suites, including plan-node recovery, late
  observations, recovery wake coordination, authenticated query and task identity.
- 16 S26U instrumentation tests passed in 23.439 seconds: the four new recovery
  tests plus twelve existing connector-fallback runtime tests.
- Repository checks and `git diff --check` passed.

### First Live Run: Failed

`stress-81086c4b-7aa1-46e5-9feb-3119f78a222e`, Codex `gpt-5.6-sol`:

- Ten independent Desktop tasks were created while phone windows were backgrounded.
- Desktop completed nine tasks with 80 numeric rows each (116.5-328.9 seconds);
  one task stalled without output and timed out after 181.9 seconds.
- The phone test received zero final results within its 600-second window.
  This is a failed end-to-end result, not a 90% product pass rate.
- Follow-up metadata inspection showed that the long prompt had been expanded by
  the dynamic team compiler into ten two-member teams. Parent runtimes were still
  waiting on team outcomes. This run did not isolate the intended single-Codex path.
- MQTT broker acknowledgements also reached 20-25 seconds during this run. This is
  observed latency, not proof that network outage caused the missing team outcomes.
- The original report and metadata-only inspection were retained locally as
  `galaxyssi-s26-background-first-run.json` and
  `galaxyssi-s26-background-first-inspection.json` in the Windows temporary directory.
- Only the verified fixture conversations were cancelled before the next run.
  Existing user conversations and other devices were untouched.

The live fixture now uses a short arithmetic instruction to avoid automatic team
expansion. Dynamic-team completion remains a separately identified acceptance gap;
the recovery unit/device results above do not certify that path.

### Second Live Attempt: Rejected Before Model Dispatch

`stress-6d06678b-83cc-4a92-a559-274a89aeb310`: the short prompt beginning
`Start BEGIN ...` was interpreted as an application-launch command. All ten
conversations returned `No launch target is available`; the harness failed its
first-submission assertion after 60 seconds. No Codex success is claimed for this
attempt. Its report is retained as `galaxyssi-s26-background-second-run.json`.
The arithmetic prompt now begins with `Calculate` and stays below the dynamic-team
complexity threshold. The two observed intent-routing weaknesses are recorded,
not silently counted as successful recovery tests.

### Third Live Run: Failed Result Delivery

`stress-36082903-6ab2-4164-ab62-e4bea0205267`, Codex `gpt-5.6-sol`:

- All ten requests reached Desktop through the intended direct connector path.
- Desktop completed eight requests and timed out two without first output.
- The phone received 128 progress/events, including running events in the
  background, but zero final answers during the 600-second wait. The complete
  test failed after 614.45 seconds. Its observed running overlap peaked at three,
  so the ten-simultaneously-running assertion is also not established.
- Peak sampled PSS was 461,584 KiB; battery temperature peaked at 34.6 C and
  Android reported thermal status 0. These are observations, not a performance SLO.
- Metadata inspection found all ten handoffs still waiting, with valid pairing
  bindings and no pending final-message bodies. No new action-ID conflict was
  observed. This does not establish successful live timeout-to-fallback recovery:
  the fixture explicitly locks Codex and has no eligible fallback.
- Read-only Desktop diagnostics found all ten terminal replies handed to its
  transport outbox. Multiple final packets remained queued for minutes; metadata
  recovery replies also arrived after their correlation windows. Thus a healthy
  MQTT connection flag alone did not establish timely result delivery. The exact
  cause of this transport delay remains unverified; do not label it a confirmed
  public-broker outage or fix it by bypassing execution identity validation.
- Original artifacts: `galaxyssi-s26-background-third-run.json` and
  `galaxyssi-s26-background-third-inspection.json`, retained in the Windows
  temporary directory. Desktop was not restarted or patched during this run.

The added timeout-query gating must be distinguished from these measurements:
the third live run used the earlier 1.1.62 build, before that final reduction in
redundant queries. The failed live result is retained as a release acceptance gap.

### Follow-Up After App Restart

A later metadata inspection found no remaining pending deliveries for the ten
fixture conversations and exactly one final assistant entry in each conversation:
eight answer-sized entries and two short failure entries, consistent with the
Desktop outcomes. The entries use each original turn's `assistant-final` identity.
This demonstrates eventual durable outcome retention after restart, not timely
background delivery or a ten-success pass. The separate snapshot is retained as
`galaxyssi-s26-background-after-restart-inspection.json`. It did not validate all
numeric rows; the opt-in inspection now reports those checks for future reruns.
