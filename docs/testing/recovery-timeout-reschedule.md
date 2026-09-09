# Retry unresolved recovery observations without resubmitting work

## Reproduced failure

On SM-T575, Android 1.1.37 (923) and Desktop 1.1.40, the opt-in live final
recovery case `live-final-1788971430217` completed its actual Chinese Codex task.
The test acknowledged its transport envelope but deliberately kept the body out
of the response inbox and transcript, then stopped the App process.

The next process failed the unchanged 60-second archived-body assertion. Two
read-only recovery queries reached the existing 8-second observation timeout.
Their authenticated transport responses arrived after each query had expired;
diagnostics recorded `response_timeout` followed by `late_or_unknown`. The
coordinator then stopped despite the persisted pending reply. No model task was
resubmitted, and no pairing, queue, or application data was cleared.

Evidence is retained under `build/live-final-1788971430217/`, including
`setup.log`, `inbox-before.log`, and `inbox-diagnostics-before.log`.

## Cause and change

`AgentRemoteRecoveryClient` reports a timed-out or rejected query and returns an
empty list. Automatic discovery previously treated that empty list as a completed
pass. The event-driven wake coordinator had no indication that work remained;
with an already-ready connection, another connection event was not guaranteed.

Automatic observation now explicitly requests a delayed retry for timeout,
publish rejection, or an observation exception. The coordinator keeps one worker
and retries with 1, 2, 4, 8, 16, then at most 30 seconds of backoff. An external
wake can interrupt backoff. Disconnect stops publication and retains the wake for
subscription readiness; scope cancellation releases the worker. A successful
pass resets backoff and does not generate an idle heartbeat. An authenticated
`unavailable` response is not treated as a transport timeout.

Each retry reads the current paginated pending-delivery store and rechecks pairing,
scope, terminal/superseded state, and active body-transfer ownership. It queries
the original execution; it never resubmits a prompt or repeats a tool side effect.
The per-query 8-second deadline, identity validation, rejection of expired query
nonces, and the acceptance test deadlines remain unchanged.

Android runtime version: 1.1.38 (924). Desktop code and version are unchanged.

## Device selection and reproduction

Live fault injection still requires explicit opt-in. The runner and instrumentation
both check the expected model, defaulting to SM-G9880. T575 testing requires an
explicit model argument; it does not silently select another attached device.

```powershell
./tools/dev/test-android-live-final-recovery.ps1 -Serial R52R90282TY -ExpectedModel SM-T575
```

After a failed phase, retain its log and resume the same source, never setup:

```powershell
./tools/dev/test-android-live-final-recovery.ps1 -Serial R52R90282TY -ExpectedModel SM-T575 -Source 1788971430217 -Phase inbox
```

The four phases verify real Provider completion, automatic exact archived-body
recovery in another process, UI consumption and Activity recreation, and another
cold start with exactly one reply in the original conversation. This is not full
device reboot, all execution-path coverage, or a P95/P99 performance claim.

The UI phase opens the target conversation through the production
`galaxyssi_open_agent` / `galaxyssi_agent_conversation_id` navigation entry point.
Current windows remember their own conversation, so changing the headless store's
global selection does not select that conversation in an existing window. Activity
recreation and the final cold phase do not reselect it; they must retain selection.
`inspectPreservedCase` is an opt-in read-only diagnostic, not an acceptance phase.
It reports only the test case's checkpoint, queue flags, entry count, hash, and
exact-body comparison, without rewriting a checkpoint or inserting any result.

## Preserved evidence after installation

The first failed case could not resume its inbox phase after the build/install
interval: its pending row had already been consumed. Scoped inspection found
`pending=false`, `inbox=false`, `terminal=false`, `assistant_entries=1`, and
`exact_transcript=true`. Its original Desktop execution still existed exactly
once. This establishes retention, not when or which App process recovered it;
it is not counted as a controlled post-fix four-phase pass. Its checkpoint and
failed logs were retained instead of reinserting the pending row or resubmitting.

The independent post-fix case `live-final-1788973000982` passed setup and inbox:
2,296 ms to subscription readiness, 7,919 ms from readiness to the exact archived
body, 10,215 ms total. Its first UI attempt timed out while showing the previously
selected window conversation. Read-only inspection nevertheless found the exact
reply once in its original transcript. That UI failure and screenshot were kept
as `ui-before.log` and `ui-screen.png`; the navigation-aware harness resumes the
same case's UI stage, not setup. The 30/60-second assertions were not extended.

The successful inbox sample is not evidence of a lower network P95 or proof that
the retry branch was exercised in that particular pass. The observed pre-fix
timeouts and deterministic retry/identity tests establish why rescheduling is
needed; network variability remains a separate performance problem.

## Verification and remaining failure

- Full Android unit run: 3,407 tests, 494 suites, zero failures/errors, five
  existing skips. The initial iteration exposed a disconnect ordering race in
  the new retry wait: signalling before assigning the connection state allowed
  an unconfined waiting coroutine to observe stale connectivity. Assigning the
  state before signalling fixed it; the regression remains in the suite.
- Debug App and AndroidTest packaging passed; Android 1.1.38 (924) was installed
  in place on SM-T575. No other device was operated or uninstalled.
- Repository guard, 73-library AArch64 16 KB audit, and QNN packaging check passed.
- The original failed case still has its exact reply once in its own transcript.
- The independent case completed actual Codex execution once and automatically
  recovered the exact archived body after process death.
- **Four-phase UI acceptance is still incomplete.** Explicit production navigation
  showed the recovered reply, but Activity recreation selected a different
  conversation. Test milestones reported `ui_launched selected_test_conversation=true`,
  `ui_visible`, then `ui_recreated selected_test_conversation=false`. The existing
  30-second visibility assertion correctly failed. No artificial re-selection,
  transcript insertion, or deadline extension was added to make it pass.

The remaining window-selection failure is outside the recovery scheduling change
and requires a separate runtime fix and same-case UI/cold restart verification.
This PR does not claim full Run Kernel recovery, full chaos acceptance, or a
five-second recovery SLO.

Build evidence: `build/recovery-timeout-retry-build-v2.log`,
`build/recovery-timeout-retry-unit-summary.json`,
`build/recovery-timeout-retry-repo-final.log`,
`build/recovery-timeout-retry-16kb-v2.log`, and
`build/recovery-timeout-retry-qnn-v2.log`. The scoped live evidence is under
`build/live-final-1788973000982/`, including `ui-diagnostics.log`.
