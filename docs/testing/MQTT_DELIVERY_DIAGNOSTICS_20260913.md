# Verified Delivery Diagnostics

## Change

Both transport policies now keep a small, separate observation window for the
diagnostic view. It contains at most 32 accepted samples per broker (96 total),
irrespective of the number of peers, conversations or windows. The scheduling
algorithm, its existing per-peer history, queue budgets and receipt semantics
are unchanged.

Samples enter only through the existing authenticated, content-bound peer receipt
acceptance hook. A broker PUBACK, wrong identity/hash, duplicate receipt, invalid
elapsed time or unattributed legacy stored-message receipt cannot produce a
delivery-time observation. Receipt verification remains the upstream handler's
responsibility; the statistics collector is not an authentication boundary.

Each sample measures an attempt's reservation time to its attributable verified
peer receipt. This is **not** prompt-to-answer latency, model duration, pure
network RTT, or a claim that the user opened an attachment. Race winners are
represented; lost attempts and unattributable completions are not latency
samples. Therefore this dashboard distribution is not a substitute for the
all-submission performance/failure benchmark.

The view reports count, latest latency and median. The nearest-rank p95 is null
until at least 30 valid samples exist, and remains a recent observation rather
than a statistically guaranteed SLO. Missing/expired data is null, not zero.
Samples older than the existing 300-second metric TTL are excluded. Network
changes clear the windows; forgetting a peer removes its observations. Public
snapshots contain aggregate counts/times only, not peer or message identifiers.

## Product Entry Points

- Android: the existing advanced protocol diagnostics page now includes the
  three broker names, recent delivery medians/p95 and sample counts, using the
  existing row styles. No data and insufficient p95 samples have explicit
  English/Chinese labels. No chat background, input control or output layout
  changes. The snapshot is read when the page is opened; it is not continuous
  background polling and does not connect or publish anything.
- Desktop: the existing loopback-only `/api/link/transport-diagnostics` response
  retains its event counts and adds `mqtt` health with `scheduling` observations.
  The existing Run diagnostics control already displays this response. `connected`
  and authenticated peer `ready` remain distinct. This checkpoint does not add
  the full human-readable broker status panel requested for release.
- Owned native test snapshots now retain scheduling observations so actual
  receipt-flow measurements can be inspected without a production deployment.

## Tests And Limits

- Initial focused Desktop selection: 93 tests passed.
- Desktop lifecycle/policy/diagnostic selection: 67 tests passed after correcting
  the new fixture to supply the peer-route adapter installed by production.
  The initial missing-adapter error was a fixture failure, not hidden as a pass.
- Three API route-body tests pass: existing counts plus transport data, loopback
  denial before observations, and no fabricated healthy response on failure.
  They execute the isolated route body, not a running HTTP server.
- Android host suite: 210 cases passed. It covers collector bounds, 29/30-sample
  behavior, expiry, duplicate/invalid/unattributed receipts, network reset and
  peer removal in addition to existing scheduling, routing and delivery tests.
  The final boundary-test rerun also passed all 210 cases (7.586s).
- The final combined Desktop selection passed 124 tests (5.025s), including the
  API route-body tests; earlier selections overlap and are not summed.
- Desktop's 37 checks and structure check passed.
- Full Android resource/Kotlin compilation passed in 7m 43s; the final-source
  incremental confirmation also passed in 3m 53s. The first attempt lacked
  `ANDROID_HOME` and failed before source compilation; corrected attempts use
  the existing local Android SDK. No SDK or dependency versions were changed.
- Device rendering, active three-path status, retry/byte/throughput presentation,
  idle power, and real Android traffic remain unverified. The connected SM-T575
  is outside the current S26U-only scope and is not operated.

This is an implementation checkpoint for PR #3045, not completion of the full
multi-broker specification. Previous failures and the remaining acceptance
matrix remain in the [progress record](../engineering/MQTT_MULTIPATH_PROGRESS.md).

## Native Observation Check

`build/mqtt-native-diagnostics-v1/report.json` passed 20 business messages and
three owned-broker failure/recovery cycles, including held receipts and process
death. Exit was 0 and both endpoint logs were empty. The final snapshots now
contain these real native receipt observations:

| Endpoint | Path | Samples | Median ms | p95 |
| --- | --- | ---: | ---: | --- |
| Left | EMQX | 6 | 421 | null |
| Left | HiveMQ | 0 | null | null |
| Left | Mosquitto | 3 | 375 | null |
| Right | EMQX | 1 | 875 | null |
| Right | HiveMQ | 3 | 375 | null |
| Right | Mosquitto | 0 | null | null |

These prove the collector is reached by actual authenticated receipt flow, and
that unobserved paths/small-sample p95 are not fabricated. Counts are bounded
current-process snapshots, not lifetime business counts: process restart and
attribution rules mean they need not sum to the test's 20 messages. No model or
Android endpoint participated; these loopback observations are not public-broker
performance rankings. Earlier benchmarks remain the performance evidence.
