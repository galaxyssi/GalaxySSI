# Android agent-scoped failover recovery

## Scope

Android 1.0.9 corrects the existing connector fallback path. This is not a new
intent router and does not change provider prompts, ASR/QNN, wire protocols,
manual model preferences, or the current timeout durations. Desktop source and
iOS are unchanged.

## Failure domains

An unaccepted request (`NOT_ACCEPTED`) or explicit delivery failure is evidence
of a failed shared transport. Untried fallbacks on that same Desktop are
excluded; other Desktops, cloud providers, and phone resources remain eligible.

An accepted agent that does not start (`NOT_RUNNING`), a stale read-only agent,
or a remote terminal execution failure is scoped to that resource. It must not
quarantine another agent on the same Desktop. A received remote terminal event
or failed response proves that the transport can receive messages, so it clears
the domain circuit without counting the failed agent request as a success.

Cancellation remains terminal. Manual selection is checked both at the native
agent fallback boundary and in the dispatch candidate list.

## Per-action attempt history

The action and encrypted session checkpoint retain:

- Selected resource and its current adapter, kind, and failure domain.
- Remaining untried candidates.
- Previously attempted resources.
- Deferred soft-failure retries and already consumed retries.
- The action ID owning the history.

Refreshing the catalog can add newly available resources, but cannot turn an
exhausted or deferred resource into an untried resource. Permanent failures are
not deferred. The existing single deferred retry for a soft-failed resource is
preserved, after untried alternatives. No new cumulative tool-call budget or
wall-clock deadline is introduced.

History is no longer truncated after twelve resources. Such truncation loses
failure evidence and can cause an endless catalog-refresh cycle. A new action,
including a subsequent long-task reviewer, starts a new history rather than
inheriting the previous action's failures.

## Normal execution lifecycle

The selected fallback action replaces the previous route in the task plan and
is persisted before dispatch. Resource-specific model and instance overrides
from the old Auto target are not sent to a different provider.

Fallback dispatch now reuses `executePlannedAction`: execute, observe, verify,
update action status, and persist. Both immediate success and asynchronous
waiting results are retained. Immediate errors retain their actual error text.
The previous secondary dispatch path discarded any result not marked as
`awaiting_response=true`.

Only route state is checkpointed here. Materialized tool output or expanded
conversation prompts are not copied into the persisted action as part of this
change.

## Verification

JVM coverage includes same-Desktop agent isolation, real transport exclusion,
manual locking, provider adapter changes, permanent and transient catalog
refresh cycles with 32 resources, 64-resource serialization, and fresh actions.

Android instrumentation uses isolated task/session stores and injected provider
results to exercise the real MobileNativeAgent execution path. Encrypted
checkpoint tests cover independent turns and catalog refresh after reopening.
Two opt-in tests are separated by an external process stop to verify persisted
fallback state in a different process.

Real provider verification is separate from injected failure tests. Successful
live Codex replies do not by themselves prove that every provider's failure
mode or latency SLO has been validated.

### S26U results, 2026-09-05

- Final stable build: `auto-failover-stable-build.log`, successful; 72 JVM tests,
  zero failures/errors.
- Device tests: seven ordinary instrumentation cases passed. The two opt-in
  process-restart phases passed separately (save PID 22161, recover PID 22231).
  This verifies the checkpoint in a different process, not full application
  recovery of every active run within the global five-second SLO.
- Live Chinese question: one real Codex reply completed, Desktop task
  `3908fdb0-b1f3-360b-8d64-237b8c19fc8c`, `agent_id=codex`, no task error.
- Phone monotonic tracing: first visible output 18.451 s, final visible output
  23.391 s, final consumer queue 129.575 ms, final receive-to-display 1.501 s,
  UI queue 0.299 ms. Desktop reports 14.043 s task execution. These are different
  measurement ranges; do not subtract unsynchronized device wall clocks.
- Cold activity launch after test cleanup: 570 ms. The previous reply remained
  visible after reopening. This is activity launch time, not a list-loading P95.
- Repository check passed. No new App crash appeared in the device crash buffer
  after the final installation; its latest existing crash is the earlier
  21:05:31 recovery issue fixed in PR #2812.
- Installed version: 1.0.9 (855). First installation time remained
  `2026-09-05 10:48:56`. Only the test APK was removed afterward.
- Installed APK SHA-256:
  `3fe6bae5378a19d957270326b9adbbc4509115b4a2fbbdfe0f0e7c029dc2a576`.

After this measurement, the user accepted approximately twenty seconds as the
current response-time target. The previous ten-second target is no longer a
hard gate for this phase. The measured 23.391 s is retained without rounding it
down to twenty; a single run is not a P95/P99 latency guarantee.

### Default device change

The user subsequently changed the default test device to S20U (SM-G9880).
The identical 1.0.9 (855) APK was installed there and its model-selection page
opened successfully, showing the paired Desktop and selected Codex Spark/low.
The quantitative measurements above remain S26U measurements; they are not
relabelled as S20U results. Further real-device validation should target S20U
unless the user requests another device.

## Remaining work

Provider-internal retry loops and multi-provider cloud candidate groups remain
separate from the outer connector trail. Consolidating their exact per-attempt
events into the unified Run Kernel, cross-device chaos tests, and P95/P99 SLO
validation remain part of the larger execution/recovery goal.
