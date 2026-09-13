# MQTT Candidate Probe Results

Production code revision: `a36b6b240`; subsequent commits only record evidence.
No production code, timeout, acceptance threshold or installed application was
changed for these probes.

## Public Compatibility Smoke

The actual Desktop pool made three verified-TLS connections, subscribed to a
fresh exact diagnostic topic, and sent **one 75-byte synthetic message per
provider**. All three payloads returned intact. No real pairing or user content
was used and no public load test was run.

| Provider | Connect from pool start | Subscription from start | Publish-to-loopback |
| --- | ---: | ---: | ---: |
| EMQX | 1500 ms | 1797 ms | 281 ms |
| HiveMQ | 6860 ms | 7235 ms | 375 ms |
| Mosquitto | 1922 ms | 2282 ms | 375 ms |

These are single observations on this PC/network, not p50/p95 or native Signal
delivery. HiveMQ's payload returned before its PUBACK was captured: its snapshot
still has one pending publish and no `broker_acked` value. Do not report three
observed PUBACKs or infer a delivery failure from that missing observation.
Output: `build/reports/mqtt-multipath/public-final-20260913.json`.

## Owned Native Small-Message Comparison

Each run uses isolated native Signal endpoints and three owned loopback TLS
brokers. There are **30 measured messages per strategy**, in shuffled blocks,
and six excluded warm-ups. Seed `20260915` fixes block order, not identity/random
path tie-breaking. Every one of **66 business messages per run** passed content,
route, durable-receipt and single-dispatch checks. Endpoint logs are empty.
No other build/test workload was started by this task during the measurements;
this shared Windows host is not an isolated performance appliance.

| Cohort | Strategy | p50 request-to-RX_STORED | p95 | Submitted business frames |
| --- | --- | ---: | ---: | ---: |
| Healthy | One available path | 891.317 ms | 1108.872 ms | 30 |
| Healthy | Automatic multi-path | 889.720 ms | 1255.935 ms | 30 |
| Primary receive loss | Healthy single-path reference | 776.215 ms | 1035.409 ms | 30 |
| Primary receive loss | Automatic multi-path with injected loss | 1652.450 ms | 2679.745 ms | 60 |

Healthy provisional gate: **FAIL**, exit 2. p95 ratio is **1.132625**, exceeding
the unchanged **1.10** limit. Both strategies submitted 658,020 business MQTT
bytes with zero redundant business frames. First-publish-to-receipt p95 values
were 988.623 / 995.756 ms; these stage percentiles cannot be added/subtracted to
establish the cause of the end-to-end percentile difference. The controller log
also retains an aMQTT TLS alert; it is not evidence of a production TLS cause.

Fault provisional gate: **PASS**, exit 0, against the unchanged **8000 ms** p95
budget. All **30** fault observations record selected-primary PUBACK, actual
receiver-side loss and alternate physical delivery. Automatic multi-path sent
1,316,040 business MQTT bytes, of which 658,020 were redundant attempts. This is
selected-primary loss, not proof that the physically fastest path was failed.
The single-path reference is healthy, not a single-path outage comparison.

Reports and raw sample/block data:

- `build/mqtt-final-native-latency-v1/report.json`
- `build/mqtt-final-native-fault-v1/report.json`
- Corresponding `build/mqtt-final-native-*-v1.log` files and endpoint logs.

## Interpretation And Remaining Work

Native correctness and alternate delivery pass these cases. Healthy small-message
non-regression is **not yet stable/passed**, and these results do not replace the
previous failed cohorts. There is no phone, real model, UI, artifact throughput,
P2 striping, radio/network energy or whole-application cold-start measurement here.
The full specification remains open. S26U is absent; SM-T575 was not operated.
No application was installed or production Desktop replaced.
