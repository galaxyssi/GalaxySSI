# Active3 A007 PPTX delivery and revision evidence

## Scope

Run `active3-warehouse-pptx-20260929-v1325` used the frozen 100-case,
1100-turn catalog, SHA-256
`945c11225d2f7268e43403c09c7f0bc8158c579168b65e3c32a4b16ba9a113bc`.
Only A007 turns 0 through 2 are covered here. The remaining eight A007
follow-ups and the full catalog remain incomplete.

Device: Samsung SM-T575 (Active3), Android app 1.3.25 (1068).
Provider: remote Codex, requested model `gpt-5.6-sol`.
The running Desktop backend was 1.3.23, started on September 29 at 18:27.
Newer Desktop source changes were not deployed to this process. This is not
acceptance evidence for the newer Desktop fixes.

## Observations

| Turn | Task | Reply terminal | Observed total including audit/UI | Delivery |
| --- | --- | ---: | ---: | --- |
| 0 | Create four-slide editable PPTX | 248.882 s | 342.596 s | Failed: original PPTX missing after 90.353 s presence wait; four PNGs received |
| 1 | Increase item B quantity by seven | 166.741 s | 204.837 s | Passed: PPTX and all four PNGs received and save hashes verified |
| 2 | Reformat for mobile reading, app backgrounded | 254.731 s | 348.471 s | Failed: page 2 and page 3 PNGs missing after 90.257 s presence wait; PPTX and pages 1/4 received |

All three turns reached a terminal reply, had stable focused reply captures,
and showed a stopped timer. Turn 2 received its final reply while backgrounded.
These findings do not prove complete artifact delivery. The instrumentation
runner's successful exit is not the business success rate.

The source-bound review in
`tools/benchmark/business-scenarios/reviews/active3-a007-20260929.json`
approves only turn 1 content. Actual received PPTX inspection found four
slides, editable text, and a native chart with values 204, 272 and 220 and a
zero value-axis baseline. Quantity total is 73 and amount total is 696.
All four received previews were visually inspected; the visible data matched
and no clipping was observed. Missing owner, dates, returns and currency unit
were not invented. Native PowerPoint editing and recalculation were not tested.

Turn 2 received PPTX also retained the values and native chart. Desktop-side
previews showed the 9:16 layout, but source-side previews cannot substitute for
the two missing phone files. No complete turn 2 content/preview pass is recorded.

## Separate late recovery observation

After the original turn 0 audit had already failed, reopening the test UI later
found its PPTX on the phone. Its 42,577 bytes hashed to
`404f5a3e5529085435c1105a4931deac6f121d027224dcf165c651da3cc07b82`,
matching the delivery ledger. Ledger registration-to-stored-receipt time was
520 seconds. A separate UI audit opened the first preview and saved it with
matching hash.

This does not rewrite turn 0 as passing. Instrumentation termination can stop
the app, so the separate observation is not proof of uninterrupted background
recovery or a precise network-only latency. Available logs do not establish
which broker or receiver step caused the delay.

## Reproduction and evidence

Raw local run directory:
`%LOCALAPPDATA%/Temp/galaxyssi-business-eval/active3-warehouse-pptx-20260929-v1325`.
It contains the original `A007.json`, catalog, received artifacts and captures.
No raw user data, credentials, screenshots or generated binaries are committed.

The continuation instrumentation ran only
`BusinessScenarioLiveDeviceTest#realBusinessConversations`, with
`business_cases=A007`, `business_turn_limit=3`, `business_turn_timeout_ms=600000`,
`business_provider=codex`, and `business_device_model=SM-T575`.
It resumed existing turn 0 evidence rather than resending the initial task.

Verify the source-bound review using `report.py --plan <run>/catalog.json
--reports <run> --reviews tools/benchmark/business-scenarios/reviews/active3-a007-20260929.json
--output <separate-summary>.json`. Keep raw reports unchanged.

## Remaining work

- Diagnose and repair incomplete logical artifact delivery, with bounded retry
  and receipt handling rather than blindly resending every chunk.
- Verify updated Desktop recovery code in the actual runtime.
- Retest foreground and background delivery, all preview pages, open/save,
  reconnection and isolation across tasks.
- Complete the remaining frozen workload. Three observations are insufficient
  for a stable p95 or a general quality claim.
