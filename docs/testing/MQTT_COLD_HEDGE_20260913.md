# Conservative Cold Hedge And Primary-Loss Measurement

Date: 2026-09-13. Full Android/Desktop multi-broker acceptance remains open.
This follows the failed repeated-order gate in
[native latency](MQTT_NATIVE_LATENCY_20260913.md), not a replacement for it.

## Production Change

The shared catalog now separates two different quantities:

- `unmeasured_path_rtt_ms = 500`: the previous neutral path-ranking estimate.
- `unmeasured_hedge_ms = 2000`: the conservative unsampled backup interval.

Both generated catalogs come from `config/mqtt-multipath.json`. The first
physical message is still immediate. Only unconfirmed ordinary small messages
and small final results have delayed backup copies, at 2s and 4s in the
sample-poor case. After twenty verified observations, the existing bounded p90
estimate applies, preferring a mature primary's own window. Critical controls
still race immediately. A detected physical failure still expedites remaining
copies; it does not wait out the cold interval. The 30s keepalive, global window,
crypto, image policy and UI are unchanged.

The previous single-available cohorts had physical-submit-to-durable-receipt
p95 values around 1.57-2.56s on this host. A 0.5s unsampled backup therefore
repeatedly created duplicate work before the original completed. The new 2s
value uses the existing maximum interval as a bounded conservative starting
point, not a claim that all networks have 2s latency. A separate ranking prior
avoids silently changing unknown-path ordering when tuning backup cost.

Regression tests still assert the exact new 2s/4s cold schedule and immediate
controls. Dispatch, revocation, wrong-receipt and quota tests now advance their
fake clocks past both configured backup times instead of accidentally passing
before a backup is due. Mirrored ranking tests prove that the longer hedge does
not redefine the unknown-path estimate.

## Primary-Loss Method

`native_latency.py --fault-primary` retains the owned loopback TLS/native Signal
and real SQLite business path. Before each of thirty measured multi-path sends,
the sender previews its actual policy's primary for the new message ID. The
receiver then drops all ingress on that one owned broker, while MQTT connections
and subscriptions remain up and the broker still sends PUBACK. The test checks
that the first actual submission matches the preview; a routing race fails the
sample rather than silently testing the wrong path.

Each sample requires an observed dropped packet, an actual primary PUBACK before
the authenticated durable receipt, and an accepted alternate-path submission.
The original ID/hash/route must produce exactly one completed business row; the
durable outbox must retire only after the real receipt. Drop state is cleared
after each successful sample. No key, ACK, plaintext, task or result is forged.
The fault hook is reachable only in the disposable local JSON-line test worker,
not an application API. Hostnames and production broker configuration are not
rewritten.

This is **selected-primary receiver-ingress loss**, not a real Internet outage
or proof that the selected path is the physically fastest. It is also not a
single-path fault/recovery comparison: the accompanying thirty single-available
messages are healthy references. The ordinary warm p95 ratio is not applied
between those unequal conditions. A separate provisional fault p95 budget of
8s was declared before the baseline run; the CLI exits 2 if it fails. There are
six excluded warmups and 66 validated business messages per run. All raw samples
and policy limits are retained. Failed/censored samples are not removed.

## Observations

Owned loopback only, same non-isolated Windows host as the earlier report.
No build or load test ran concurrently with the timed cohorts. Values are
nearest-rank milliseconds from request entry to authenticated RX_STORED commit.
Business frame counts exclude control/ACK/TLS traffic and lower-layer retries.

| Run | Strategy | n | p50 | p95 | Submitted frames |
| --- | --- | ---: | ---: | ---: | ---: |
| Before cold change, seed 20260913 | Healthy single available | 30 | 1321.85 | 1881.73 | 30 |
| Before cold change, seed 20260913 | Primary-loss multi | 30 | 2648.27 | 2941.04 | 64 |
| After cold change, seed 20260913 | Healthy single available | 30 | 1253.49 | 1879.38 | 30 |
| After cold change, seed 20260913 | Healthy automatic multi | 30 | 1244.56 | 1836.07 | 30 |
| After cold change, seed 20260914 | Healthy single available | 30 | 1157.80 | 2058.49 | 30 |
| After cold change, seed 20260914 | Healthy automatic multi | 30 | 1264.62 | 1768.84 | 30 |
| After cold change, seed 20260913 | Healthy single reference for loss run | 30 | 1270.16 | 2429.99 | 30 |
| After cold change, seed 20260913 | Primary-loss multi | 30 | 2689.36 | 3010.33 | 61 |

The two post-change healthy ratios are 0.977 and 0.859, within the provisional
1.10 budget; each run passed all 66 business checks. Multi-path submitted no
redundant business frames in either run (658,020 bytes per thirty-message
strategy), compared with 13 redundant frames in the earlier failing seed-13
cohort. These are two host-local observations, not Internet/provider, Android
or all-load stability acceptance.

The post-change primary-loss run passed all thirty injected samples and 66
business checks. Its p95 rose from 2941.04ms to 3010.33ms (about 69ms in these
two local cohorts), within the predeclared 8s budget. Submissions fell from 64
to 61 business frames. The thirty dropped originals necessarily require thirty
alternate copies; the extra third-copy count fell from four to one. This is not
evidence of generally faster fault recovery or a statistically significant 69ms
regression. It records the observed tradeoff instead of hiding it. The healthy
single-path reference in that run also varied materially.

The experiment does not provide thirty independent completely cold connections:
each six-block run retains one identity/ratchet and has warmups. The sample-poor
transition is exercised, but cold-start distributions remain a separate gate.

Reports:

- `build/mqtt-native-primary-loss-before/report.json`
- `build/mqtt-native-cold-hedge-warm-v1/report.json`
- `build/mqtt-native-cold-hedge-warm-v2/report.json`
- `build/mqtt-native-primary-loss-after/report.json`

The pre-change fault run used the 0.5s catalog loaded at worker startup. Later
runs also include the actual per-endpoint policy limits in their JSON report.

## Regression Verification

- 94 Python policy/dispatch/bridge/route cases passed after the final timer
  updates (23.423s, alongside Android compilation, not a speed measurement).
- 16 measurement, CLI and isolated ingress-fault cases passed. They distinguish
  PUBACK from durable commit, preserve first ACK timing, reject unknown fault
  paths and return a failing exit code for either failed provisional gate.
- Five shared-catalog generation/validation tests and generated-file check passed.
- Desktop UI/structure check passed: 37 tests, no UI source changes.
- Final Kotlin host regression passed 196 cases (8.838s).
- The normal full-runtime Android build and instrumentation Kotlin compilation
  passed in 9m 32s, with 81 focused JVM cases and no failures/errors/skips.
  That pre-receipt-retry APK is 427,091,070 bytes, SHA-256
  `D51182A4D846FA4493686F0A0214D1CCF5DE2B2D7DE195E67AAF111253249C67`.
  It is not evidence that later receipt-retry changes were packaged or installed.

The subsequent native fault smoke **failed** in the all-offline/single-path
recovery case: the receiver had one correctly dispatched business row, but the
sender retained its published outbox row past the 25s test deadline. Both saved
endpoint error lists were empty. The receiver's saved snapshot preceded the
sender timeout, so it does not by itself locate every failing stage. Artifacts
remain in `build/mqtt-cold-hedge-native-smoke/last-snapshots.json` and the sibling
log. This failure was not discarded or relabeled as a pass by extending the
deadline. Follow-up investigation and verification are recorded in
[stored receipt recovery](MQTT_RECEIPT_RETRY_20260913.md).

The existing packaged Desktop is running from this worktree's `dist` directory.
The packager would stop it, so it was not repackaged or restarted during this
checkpoint. Its process presence is not proof that the new source is deployed.

## Remaining Scope

This does not complete the real image/file/video, block striping, 100KB/boundary/
5MB/21MB/larger transfer, control-under-load, QR/pairing, ten real windows/model
runs, Android headless lifecycle, Doze, cellular/weak-network and power gates.
Those full specification requirements remain active. S26U is not connected;
the connected SM-T575 is not a substitute and was not operated.
