# Native Cancellation Under Attachment Load

## Method And Scope

`tools/testing/mqtt_owned_lab/native_control_latency.py` starts two isolated
native Signal/Desktop endpoints and three owned loopback TLS brokers. No public
broker, production Desktop, phone or model provider is used. Identities, stores,
tasks and attachment files stay in the disposable owned-lab workspace. Trust
bundles are exchanged by the controller, not by the product QR pairing UI.

The receiving endpoint creates external tasks in the real durable task manager,
without launching a model process. Each task has a separate task/conversation/
turn/source-message identity. The sender publishes a real `agent_task_cancel`;
the receiver's production dispatch, identity checks, cancellation and persistent
task state run unchanged. Only the phone-side terminal-event consumer is a
fixture. It accepts a matching authenticated `cancelled` event and timestamps
it, rather than treating a broker PUBACK or durable message receipt as task
completion. Each control request must have one completed dispatch attempt and a
persisted cancelled task. This does not verify stopping a real model subprocess.

Each run contains one excluded warm-up, 30 idle cancellations and 30 measured
cancellations during one 32 MiB attachment. The attachment requests use the real
16-chunk receive window; the controller publishes groups of four 256 KiB chunks
before a measured control. Sender-local monotonic timestamps must prove at least
one such chunk was queued but not durably acknowledged when that control began.
The final source, received and streamed SHA-256/length must agree, with exactly
one available contact artifact. All 128 chunks must be received.

This sender uses the Desktop classifier for phone-shaped
`input_attachment_chunk`, which is `MESSAGE`, not Android's `CHUNK`. Therefore
this tests cancellation competing with durable attachment ingress, **not**
Android/P2 striping performance or a saturated sustained-load capacity bound.
The fixed idle-then-loaded order is a measurement limitation. Runs must not be
used to claim a randomized causal comparison or Internet performance.

The predeclared provisional budget is loaded cancellation-result p95 <= 8000ms.
The CLI exits 2 if this budget fails even when all business checks pass. Failed
and incomplete runs are retained. This is not the full specification release
gate. The optional `--single-path` stops two owned listeners; it is a single
available-path transport baseline, not a one-connection resource baseline.

## Reproduce

Use the existing two isolated Python environments: the controller needs aMQTT
and TLS tooling; endpoints need the Desktop/native Signal runtime and Pillow.
Set `JAVA_HOME` to the installed JDK. Keep other build/load tests stopped during
measurement and select a fresh output directory for every run.

```powershell
& $controllerPython tools/testing/mqtt_owned_lab/native_control_latency.py `
  --endpoint-python $endpointPython `
  --report-dir build/mqtt-native-control-loaded-v2
```

Reports retain per-control sender timestamps, physical publications and bytes,
authenticated receipt commits, cancellation-result receipt times and overlap
evidence. From v2, receiver-local task/dispatch/reply-encryption timestamps and
reply publication/receipt measurements are also retained. Durations on either
endpoint are calculated using that endpoint's monotonic clock; clocks are not
subtracted across machines. Full artifact controller time includes deliberate
control probes, ledger checks and polling, not just transfer time.

## First Run

`build/mqtt-native-control-loaded-v1/report.json`:

| Automatic three-path cohort | n | RX_STORED p50 | RX_STORED p95 | Cancel result p50 | Cancel result p95 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Idle | 30 | 965.47ms | 1544.34ms | 2312.51ms | 4896.93ms |
| Attachment active | 30 | 2361.21ms | 3804.46ms | 4625.82ms | 8096.08ms |

All 61 cancellations (including warm-up) and 32 MiB artifact checks passed;
all 30 loaded samples had actual unacknowledged chunks at their start. Artifact
controller completion was 219.906s. Its SHA-256 was
`c539e9b0e61d579fab6bdb87ab460ca11cc9704ccef711e2fa8c15d9dc123dcc`.
No native/cleanup errors were recorded. The provisional latency gate **failed**
and the process exited 2. Maximum loaded cancellation result time was 8418.14ms.

Each cohort submitted 90 control MQTT frames (30 per owned path), 1974060 counted
bytes, including 1316040 redundant bytes. This is the intended critical-control
race, not a claim that ordinary messages or attachments are triplicated. These
figures exclude other protocol/background traffic and IP/TLS overhead.

The difference between delivery receipt and cancellation result motivates
additional local stage measurements; this first run alone does not locate the
delay in task storage, cryptography, publication or receiving dispatch.

## Instrumented Repeat

`build/mqtt-native-control-loaded-v2/report.json` used the same production code
with additional test-only receiver stages:

| Automatic three-path cohort | n | RX_STORED p50 | RX_STORED p95 | Cancel result p50 | Cancel result p95 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Idle | 30 | 990.31ms | 1564.71ms | 2374.54ms | 3611.82ms |
| Attachment active | 30 | 2146.64ms | 3284.77ms | 4226.38ms | 6760.19ms |

All 61 task cancellations, 30 overlap checks and the complete 32 MiB artifact
passed again. The artifact hash was unchanged; controller completion was
206.984s. Native/cleanup errors were absent and the provisional gate passed
(exit 0). Each cohort again submitted 90 control frames and the same counted
bytes as v1. First authenticated-ready observations were 846.84/324.73ms, versus
372.04/283.99ms in v1; these are individual startup observations, not p95, and
exclude native JVM/identity startup. No concurrent build/load tests were run;
unrelated host activity was not controlled. **No production optimization occurred
between v1 and v2; the timing difference must not be called a fix or speedup.**

Receiver-local loaded stages (30 observations, nearest-rank p95):

| Stage | p50 | p95 |
| --- | ---: | ---: |
| Business cancel dispatch entry to terminal-event callback | 20.90ms | 104.57ms |
| Terminal-event callback to reply encryption entry | 96.71ms | 120.32ms |
| Reply encryption entry to durable queue commit | 86.34ms | 136.75ms |
| Reply queue commit to first physical publication | 24.07ms | 36.67ms |
| Reply physical publication to its durable ACK | 1031.66ms | 2023.16ms |
| Complete business cancel dispatch call | 280.85ms | 624.70ms |

The stages overlap (the dispatch call includes reply generation), and percentiles
must not be added or subtracted as if they described one request. For the slowest
loaded control (7202.49ms sender-local completion), its receiver's dispatch took
338.81ms and reply queue-to-publication took 20.62ms. Those boundaries do not
explain most of the end-to-end delay. This narrows further investigation toward
pre-dispatch receive/ACK handling and the return receive path, without assigning
unmeasured time to a particular lock or broker. In particular,
`_deliver_stored_application` calls `_ack_stored_application` before dispatch;
that includes both the authenticated attempt receipt and a Signal receipt.
Those paths need separate timing before changing their safety/confirmation
semantics. There is no justification here for deleting an ACK or bypassing
Signal/receive persistence to obtain a faster score.

Verification of the test tooling: **29 unit tests passed** across the six native
measurement/fixture modules (9 endpoint tests in the endpoint environment and
20 controller tests in its aMQTT environment); Desktop **37 checks** and its
structure check passed. The test code rejects mismatched task events, missing
cancel completion, absent chunk overlap, exhausted fixture bounds and a failed
performance gate. These tests are not additional measured control samples.

## Remaining Acceptance

Single-path comparisons, cross-time/order repetitions, faulted large-file
control measurements and true Android/P2 sending remain open. So do real
provider interruption, phone UI, public-provider compatibility, App/App pairing,
ten real windows/tasks and Android background/power measurements. No phone was
operated or installed, and the running production Desktop was not replaced.
