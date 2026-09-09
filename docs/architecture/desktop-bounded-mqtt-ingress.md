# Bounded MQTT Ingress

Desktop 1.1.28 replaces a thread and unbounded queue per active paired route with
a bounded wire-processing pool. This is separate from the execution-task pool:
Signal envelopes must be processed serially per relationship before their
App/conversation/turn/task identity can be authenticated and decoded.

## Bounds And Fairness

| Resource | Default bound |
| --- | --- |
| Concurrent inbound handlers | 8 |
| Waiting messages, all routes | 10,000 |
| Waiting messages, one route | 128 |
| Retained wire buffer charge, all routes | 64 MiB |
| Retained wire buffer charge, one route | 8 MiB |
| Idle worker retirement | 5 seconds |

Wire charge includes payload bytes, UTF-8 topic bytes and a 256-byte bookkeeping
allowance. Active handler buffers remain charged until the callback finishes;
the limits do not only cover queued messages. These are admission accounting
bounds, not an exact process-RSS guarantee. Paho's current callback, decrypted
representations, reassembly, sidecar processes and other pipeline queues have
their own resource behavior and are not measured by this gauge.

Only one handler can own a route at a time. A ready route receives one message
and returns to the end of the ready queue if it still has work. New connections
do not create new threads. A stalled relationship consumes at most one worker;
other ready relationships can use the remaining workers. This does not eliminate
the need for bounded timeouts in cryptographic and downstream handlers.

The pool creates threads lazily and retires idle threads. Failed handlers release
their byte charge and cannot strand later messages. A thread-creation failure
without any available worker rolls back admission; rejected routes do not leave
empty lanes in the registry.

## Backpressure Contract

`on_mqtt_message` only resolves the opaque route and attempts admission. It never
waits for capacity or runs decryption on the Paho network callback. Unknown topics
and oversized MQTT envelopes retain their existing early rejection behavior.

At a global/route message or byte limit, the envelope is not handed to the
decoder, no application delivery ACK is emitted, and no new thread is created.
The existing reliable sender must retry the unacknowledged application message.
A retry is admissible once capacity is available. Warnings are rate-limited to
one per five seconds, while rejection counters retain every admission failure.

This does not change Paho's broker-level MQTT ACK behavior: a broker PUBACK is
not the GalaxySSI application delivery ACK. There is no new promise to persist
every raw packet. Ephemeral messages without application retries can be lost
under overload or shutdown. No global reconnect is triggered by one busy route.

## Stop And Restart

Normal bridge stop disables new admission and cancels waiting encrypted packets.
It does not acknowledge the discarded packets. Active handlers retain ownership
and byte charge until they exit. The closed pool remains visible while draining;
a replacement cannot begin decrypting the same relationship concurrently.

After the old workers exit, a later bridge start/admission can create a new pool.
Closing a window still does not redefine task cancellation; this pool owns only
inbound wire processing, not the durable task lifecycle or remote execution lease.

## Diagnostics

`/health` exposes `message_bridge.ingress`: limits, active/pending counts, retained
bytes, high-water marks, accepted/processed/cancelled counts, rejection reasons,
worker count, and accepting/closed state. No route IDs, topics, secrets or message
contents are projected. `accepted` means wire admission, not authentication or
model success. `processed` counts handler attempts; protocol errors caught inside
the handler are not necessarily represented by the pool's `failed` counter.

## Verification Scope

`test_mqtt_inbound_pool.py` covers FIFO/rotation, concurrent producers, byte and
message budgets, active buffer accounting, thread-creation failure, idle exit,
cancel/drain behavior, and 10,000 waiting routes with exactly three blocked
workers. The synthetic load test processes simple fixture values, not real
Signal/model traffic or 10,000 model processes.

`test_mqtt_route_dispatch.py` additionally verifies real ingress admission does
not invoke a decoder/ACK path on overflow, the same packet can be retried, a
draining processor cannot be replaced early, and late packets do not reopen a
stopped bridge. Its message handlers are test doubles; this is not a broker
overload acceptance test.

Real worker clients, automatic normal-App offload, worker-side monotonic lease
deadlines, safe remote cancellation/reassignment, artifact integration and
multi-host fault tests remain separate unfinished parts of the larger goal.

## September 9, 2026 Validation

- Initial inbound/route/lifecycle/timing regression: 48 tests passed in 8.12
  seconds. The 10,000-route synthetic pool test took 0.26 seconds in that run.
- Expanded task, worker and all MQTT regression: 514 tests and 233 subtests passed
  in 82.37 seconds. This overlaps the initial suite; counts are not additive.
- Root repository checks passed. Desktop checks passed all 29 Node tests plus
  structural checks.
- Desktop was closed normally only after confirming normal/control execution
  pools were idle, then started from the 1.1.28 checkout with existing paired
  state. Health reported ready, MQTT connected, 10/10 subscriptions and the new
  eight-worker/64-MiB ingress limits. Startup traffic was processed with zero
  admission rejections; this is not a model roundtrip test.
- A planned S20U run of ten conversations/twenty text-image requests with health
  sampling was NOT executed. The tool policy rejected its ADB launch command
  before execution, and read-only process inspection found no running delivery
  instrumentation. No equivalent launch workaround was attempted. No result or
  stress score is claimed for this version's real-device path.
- No Android source changes or APK rebuild were made in this change. The prior
  S20U Android installation is 1.1.12 (898); the successful 1.1.27 Desktop device
  test belongs to the previous change and is not evidence for this version.

Outstanding acceptance includes the 1.1.28 real text/image regression, actual
broker overload/retransmission behavior, and independent encrypted multi-node
load. The queue tests and healthy startup do not substitute for those checks.
Main was fetched and synchronized through `77d907755` before submission; its
final delta was Android-only hybrid retrieval work and did not alter the tested
Desktop source or the installed Android package.
