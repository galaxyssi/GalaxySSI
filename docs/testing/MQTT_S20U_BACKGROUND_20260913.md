# S20U Native Background Round Trip

Date: 2026-09-13. Target only S20U SM-G9880, serial `R5CN319CESA`.
Installed App 1.1.114 (1000), running Desktop 1.1.51. No data was cleared,
no other phone was operated, and neither package was replaced during this test.

## Executed Scenario

The user completed real QR pairing. Desktop `/health` then reported one
configured/ready peer and all three public TLS paths connected and subscribed
(7 active, 0 pending per path), Signal sidecar ready, automatic selection,
and no ingress failures. This supersedes the earlier pre-scan deployment state.

A fresh App conversation submitted this bounded test at approximately
09:41:41 local desktop time:

```text
MQTT_S20U_20260913_A. Reply only MQTT_S20U_OK. Do not use tools.
```

Immediately after sending, the phone was returned to its launcher. It stayed
there while the task executed. Returning to the existing MainActivity showed
exactly one assistant reply, `MQTT_S20U_OK`, with the correct test conversation
and Codex / DESKTOP-T14 route. The UI showed 39 seconds processing time.
Desktop task `29730a10-3460-3142-b2d7-67d958777014` is completed with the same
result, attempt 1 and execution generation 1. No task was restarted by the test.
Evidence: `build/mqtt-s20u-background-result.png` and
`build/mqtt-s20u-test-return.xml`, plus matching content-free timing journals.

## Measured Boundaries

Differences below use each endpoint's own monotonic clock, never subtraction
between phone and Desktop clocks. One sample is not a p50/p95 benchmark.

| Boundary | Milliseconds |
| --- | ---: |
| Phone send start to durable request queued | 2653.629 |
| Phone send start to verified final response received | 15771.803 |
| Phone final received to final consumption started | 21871.624 |
| Phone final consumption to accepted outcome | 925.411 |
| Phone outcome accepted to runtime finalized | 1628.965 |
| Phone send start to final checkpoint persisted | 40271.222 |
| Desktop first response outbox queue to dispatch | 243.656 |
| Desktop first response outbox queue to authenticated peer receipt | 2340.744 |
| Desktop agent started to task completed, tracer | 7556.844 |

The task's separate wall-clock execution field reports 7569ms; it is not the
same clock/sample boundary as the tracer. Visibility occurred only after the
test returned to the App; time spent intentionally on the launcher is not
network latency. The first outbound response has a confirmed peer-received
event, not just PUBACK. Subsequent recovery traffic also received acknowledgments.

## Confirmed Follow-Up

Most of the extra delay is after the phone has received the final result.
`MainActivity.onPause` removes `agentConnectorResponseListener`.
`MessageService` persists the reply through `AgentConnectorResponseBus`, but
there is no active page listener to immediately consume it. The log then shows
`connector_inbox_page replies=1`, `agent_run_recovery reason=stall` and final
consumption around 09:42:20, matching the 21.9s gap.

Required next change: durable response arrival must wake the process-owned
task recovery/consumer promptly, independently of an active page. Keep receipt
commit ordering, exact conversation/turn/generation checks, bounded work,
multi-window deduplication and background plaintext-clearing policy. Do not
simply retain Activity references forever or display queue acceptance as final.
The delay is investigated, not fixed in this baseline checkpoint. See the
subsequent implementation and installation below; its device retest is separate.

The running Desktop also logs an existing reputation ledger
`head_signature_invalid`; reputation recording was deferred while the task
and reply still completed. No integrity check or ledger was removed to pass.
That warning requires separate repair before claiming full-system health.

## Acceptance Limit

This proves one real Android/Desktop paired model task and its reply complete
while the App is backgrounded. It does not prove direct-contact duplex,
App/App, attachments/open/save, deliberate public-provider failover, ten
windows, process death/reboot/Doze, latency distributions or battery impact.
Public traffic was limited to this small task; faults and load remain on owned
brokers. The complete multi-broker development objective remains unfinished.

## Paused-Window Consumer Checkpoint

App 1.1.115 (1001) now keeps the final-response listener registered until
`onDestroy`, rather than unregistering on `onPause`. Stream/UI listeners still
detach on pause, and background plaintext clearing is unchanged. Final replies
are committed to the existing encrypted inbox before notification, then use the
existing runtime restoration, execution identity checks, task supervisor and
finalization path. The transport receipt is not changed into a task-completion
claim.

`AgentConnectorResponseRouter` holds weak consumer references, prefers an existing
task owner, and stops after one live consumer accepts the dispatch. Foreground
or paused windows can be fallbacks when another consumer rejects admission or
its executor has closed. Registration is idempotent; destroyed Activities remove
their listener before shutting down their executors. No new permanent thread,
MQTT connection or second task ledger was introduced.

One accepted callback per dispatch is not a global exactly-once guarantee:
concurrent duplicate arrivals still depend on the existing durable inbox,
identity/generation guards and supervisor. If a selected Activity dies after
admission, the reply remains durable for recovery. If every Activity is destroyed,
there is not yet a fully headless final-response consumer. Those lifecycle cases
must not be reported as fixed by retaining paused-window listeners.

### Executed Checks

- Normal full-runtime Gradle build and focused unit tests passed in 6m 37s.
  Evidence: `build/mqtt-background-app-1.1.115-v1.log` and the Gradle XML reports.
- 43 tests passed, zero failures/errors/skips: response router 6, response codec 9,
  inbox retention 6, stream bus 4, stream handoff 2, final identity 6, late response
  policy 5 and task identity 5. Existing cases overlap prior verification.
- New router cases cover task-owner preference, ten synthetic consumers,
  repeated registration, rejected/closed/throwing consumers, no consumer and
  100 concurrent distinct arrivals. These are JVM tests, not ten real App windows.
- Full APK SHA-256:
  `EE922372978D77E0F352624496870F59D9362EC927C14609DC6B1DC062BBB48F`.
  No native/runtime packaging exclusions were used.
- `adb -s R5CN319CESA install -r` succeeded. The installed package reports
  `versionName=1.1.115`, `versionCode=1001`. No data or pairing was cleared.
- Running Desktop remains 1.1.51 for a controlled Android-only comparison.
  Its health reports one ready peer, all three TLS paths connected, four active
  subscriptions per path, no pending subscriptions and no ingress failures.

### Device Retest Status

After installation the phone foreground moved to another App playing a video.
UI automation was paused and the user was asked before taking over the screen.
No post-fix background model request has been sent yet, and there is no measured
post-fix latency improvement to claim. The pre-fix 21.9s wait remains the baseline.

The next retest sends a new uniquely marked, small real Codex request, backgrounds
the App immediately, checks the phone's own monotonic receive/consume/checkpoint
timestamps while it remains backgrounded, and then verifies one reply in its
original conversation. All-hosts-destroyed recovery, ten real windows and wider
transport/lifecycle acceptance remain separate required work.

### Subsequent User-Requested S26U Installation

The user then changed the installation target to S26U. ADB identified
SM-S9480, serial `R5GL546G3LZ`; S20U was no longer connected. The same verified
full APK was installed with `install -r`, and `dumpsys package` confirmed
1.1.115 (1001). No data was cleared, no chat UI was operated and SM-T575 was not
touched. This is installation verification only, not a S26U background test or
confirmation that its existing pairing uses the new multi-broker protocol.
The pending S20U UI test was not continued after this device change.
