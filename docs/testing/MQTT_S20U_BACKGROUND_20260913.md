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
The delay is investigated, not fixed in this checkpoint.

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
