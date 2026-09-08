# Android Window Live Stress: 2026-09-08

## Result

**Overall acceptance FAILED; do not merge as fully accepted.** Background execution and receipt succeeded, but returning to window 4 did not render its final answer within 45 seconds. A subsequent persistent-transcript inspection found that runs 4, 5 and 6 contained a delivery-failure message instead of their previously received answers. This is not merely a repaint delay.

- Device: SM-T575, Android 13, app 1.1.3 (889), commit `82b775e5b`.
- Target: the already paired Codex Agent on DESKTOP-T14. Requested model: `gpt-5.6-sol`. This is the requested route, not an independent attestation of the provider's underlying model.
- Ten real document Activities were created. Each submitted a unique bounded arithmetic prompt through the actual composer. No mock replies, delegated tools or artificial sleeps were used.
- Ten submissions took 435 ms. Each requested 80 explicit arithmetic rows plus a unique BEGIN/END marker.
- Another document was foregrounded, the first document was destroyed, and Home was pressed. Android activity diagnostics subsequently confirmed Samsung Launcher as the top resumed Activity.
- All ten final answers arrived while all test windows were backgrounded. All 800 arithmetic rows and ten END markers matched their own request. No cross-conversation answer mix-up was detected in the received payloads.
- Windows 1, 2 and 3 displayed their matching final answer after returning. Window 1 had been destroyed and recreated. Window 4 failed the render assertion; later windows were not reached by that assertion loop.
- Instrumentation duration: 608.11 seconds, one failed test. No app crash was observed in this test interval.
- A separate inspection, with no new model requests, found correct ASSISTANT answers in 7/10 stored conversations. Runs 4, 5 and 6 instead stored the localized message "Message not delivered; check the connection and retry". The original ten received answers remain in the captured stress artifact; receipt success must not be mistaken for successful final transcript retention.

## Concurrency Evidence

These are different measurements and must not be conflated:

| Measurement | Observation |
| --- | --- |
| Real document windows | 10 |
| Requests submitted in one batch | 10 |
| Desktop task manager records reaching completed | 10 |
| Overlap of all ten Desktop started/completed intervals | 43.581 seconds |
| Peak Android-observed `running` statuses before receipt | 7 |
| Simultaneous provider inference kernels | Not observable |

Desktop `started_at` is set at worker entry before the runner call. Its interval includes setup, transport and provider waiting, not just model inference. MQTT status arrival is delayed/coalesced and cannot establish exact provider concurrency. The test's strict ten-`running`-statuses assertion was not reached because the earlier UI assertion failed; its observed peak would not satisfy that threshold either.

## Latency and Device Cost

Time from composer click until the test observed a durable inbox or transcript answer, sampled approximately every two seconds:

- Minimum: 83.311 s.
- Median: 515.418 s.
- Maximum and nearest-rank p95 for this ten-sample run: 533.489 s.
- Sorted values (s): 83.311, 100.530, 124.131, 508.655, 510.896, 519.939, 524.146, 531.225, 533.155, 533.489.
- Background app-process PSS: 370,951 to 454,977 KiB, approximately 362 to 444 MiB.
- App-process CPU time increased 863.885 s across 529.008 s of background samples, about 1.63 CPU cores on average. This includes instrumentation, report serialization, MQTT and application work; it is not an idle production baseline.
- Battery sensor: 32.4 to 33.6 C. Android thermal status reached LIGHT (1).
- USB power was connected. This run does not measure battery drain or prove Doze survival.
- The observer recorded 1,480 task events. Streaming/progress volume and transport contention merit profiling; model latency cannot be isolated from this experiment alone.

## Reproduction

The stress test is opt-in because it invokes the configured real model ten times. It refuses devices other than SM-T575 and does not change route capacity, encryption, global model selection or user conversations. Test conversations are private and retained for diagnosis.

```powershell
adb -s R52R90282TY shell am instrument -w -r `
  -e run_live_stress true `
  -e class com.galaxyssi.chat.AgentWindowLiveConcurrencyTest#tenRealCodexRequestsWhileBackgrounded `
  com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner
```

The optional `inspectPreviousStressResults` method uses `-e inspect_live_stress true` and inspects existing test records without making new model calls. Do not run instrumentation against a user's active workload: it owns the test app process for its duration.

Artifacts are under the ignored `build` directory: `window-stress-device.log`, `window-stress-report.json`, `window-stress-desktop-timings.json`, `window-stress-home-confirmed.png`, `window-stress-runtime.log`, `window-stress-inspect-device.log`, and `window-stress-stored-results.json`. The first automatically captured Home screenshot preceded completion of the Home transition; use the later confirmed screenshot instead.

## Remaining Work

1. Fix late delivery-failure handling of an already-received final result, then verify final-result projection on return to every background window. The receipt success above must not conceal this failure.
2. Audit transport failure and per-Activity timeout handlers against already-durable final responses. During this test, terminal-response discard logs appeared for the first three completed source IDs while the app was still backgrounded. `AgentDeliveryFailureRecorder.record` unconditionally marks pending delivery terminal, and `finishAgentDeliveryFailure` has a fallback that also marks terminal; neither first checks for a recorded authenticated final result. These are concrete investigation points; no production fix is included in this testing commit.
3. Add sequence-aware status measurements and Desktop start/finish evidence to distinguish accepted, waiting and running work.
4. Profile the long tail and high event-processing CPU cost before claiming efficient ten-way execution.
5. Repeat the complete real-model test after fixes, then separately test process death, Doze and disconnection. Closing an Activity is not equivalent to force-stopping the application.
