# Authoritative window selection across recovery and recreation

## Evidence and cause

The real Codex recovery case `live-final-1788973000982` recovered its exact body
after App process death, and persisted exactly one assistant reply in conversation
`58c347ad-9c3c-401b-af13-e502b1cd1ae5`. The UI opened that conversation using the
production navigation intent and showed the expected reply. Immediate Activity
recreation then selected a different conversation and failed the unchanged
30-second visibility assertion.

Milestones in `build/live-final-1788973000982/ui-diagnostics.log`:

1. `ui_launched selected_test_conversation=true`
2. `ui_visible`
3. `ui_recreated selected_test_conversation=false`

There were two competing persisted selectors: the transcript store's window key
and the window controller's selected-conversation record. Navigation updated the
former immediately. The controller did not update the latter until initial
hydration finished. MainActivity restored the latter first, overwriting the newer
selection if the Activity recreated during that interval. Waiting longer in the
test would conceal the race rather than fix it.

## Change

Window-scoped transcript stores now read and write the same encrypted selection
record as the window controller. Switching a conversation commits that selection
immediately, without waiting for rendering, draft save, or hydration callbacks.
Creating an unsent draft clears the previous selection. Global/headless transcript
selection remains separate; unrelated windows retain independent selections.

Existing per-window transcript selectors migrate into the authoritative store
before their legacy keys are removed. Existing unsent drafts take precedence over
stale selected records. Draft text, attachment references, scroll anchors, models,
messages, pairing, and transport are not replaced or cleared.

Android version: 1.1.39 (925). No Desktop runtime change.

## Validation plan

- Run the full existing Android unit suite and package checks.
- Run `AgentWindowSelectionDeviceTest` against the old installed App before
  installing the new App, then against the new App. The tests use unique window
  keys and conversations and delete only their own test conversations.
- Resume the original recovery case's UI phase. Do not regenerate its reply,
  reinsert its inbox body, or change its model task.
- Run the subsequent cold-start phase with no explicit conversation selection.
- Keep the existing visibility/identity/hash/deduplication assertions unchanged.

The live harness's read-only inspection is diagnostic only; passing that method
does not establish visible UI recovery. Full project Run Kernel, chaos, all
Provider paths, and device reboot acceptance remain broader requirements.

## Results on SM-T575

Full build succeeded in 6m 11s. The existing Android unit suite reported 3,407
tests in 494 suites, zero failures/errors and five existing skips. Repository,
73-library Android AArch64 16 KB, and QNN package audits passed.

The same new instrumentation APK was first run against installed Android 1.1.38:
all four `AgentWindowSelectionDeviceTest` cases failed with the expected stale or
missing window selection. After in-place installation of 1.1.39, all four passed
in 0.921 seconds. The two existing window-selection/draft and document-recreation
tests also passed (16.046 seconds). Only their own generated conversations were
deleted; user data and pairing were retained.

The preserved real recovery case `live-final-1788973000982` then completed its
previously failing UI and subsequent cold-start phases without recreating the
Provider task or its reply:

| Measurement | Elapsed |
| --- | ---: |
| First visible reply | 2,564 ms |
| UI launch, visibility, recreation, deduplication | 3,627 ms |
| Subsequent cold-start visibility | 2,582 ms |

Both selection milestones were true after the fix; the original transcript had
exactly one matching reply and Desktop still had exactly one completed execution.

An additional case, `live-final-1788974433882`, ran all four phases consecutively
on 1.1.39 with no intermediate code install or manual selection:

| Measurement | Elapsed |
| --- | ---: |
| Subscription readiness | 2,094 ms |
| Readiness to exact recovered body | 13,775 ms |
| Connection start to recovered body | 15,869 ms |
| First visible reply | 29,912 ms |
| UI launch, visibility, recreation, deduplication | 30,850 ms |
| Subsequent cold-start visibility | 2,269 ms |

All four original assertions passed, and Desktop again had only one completed
execution for that case. Its recovery diagnostics include a query timeout,
another query, rejection of expired responses, and eventual exact-body recovery.
The batch also includes unrelated unavailable observations; its aggregate outcome
must not be interpreted as failure of the recovered test task.

**Performance is not accepted by these passes.** The slow first-visible sample
is retained, not excluded. Startup tracing records 9,646 ms for `insight_count`
and 23,092 ms for global runtime background initialization. Those overlap other
work and do not by themselves explain the entire 29,912 ms interval. Inbox
consumption and startup dependency ordering require a separate investigation.
Neither a representative percentile nor the five-second recovery SLO is proven.

Evidence: `build/durable-window-selection-{before,after,existing-device}.log`,
`build/durable-window-selection-unit-summary.json`, the build/audit logs with
that prefix, and `build/live-final-1788974433882/` (four phase logs, recovery
diagnostics, UI startup timing, and one-execution verification). The preserved
earlier case's failed logs remain alongside its successful resumed UI/cold logs.
