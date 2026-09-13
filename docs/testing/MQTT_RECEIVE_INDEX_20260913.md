# Receive Backlog Query And Native Latency

## Observed Query Defect

After completed-body compaction was added, every new receive admission checked
for eligible deferred large bodies. With 10,000 small completed records for one
peer, SQLite chose the message index as the outer loop, visited all 10,000
entries, looked up each body and used a temporary sort, even though none could
be compacted. The deterministic pre-fix regression recorded 130,000 SQLite VM
instructions. The receive database lock spans this query.

The new partial index `signal_large_body_candidates` covers only bodies at least
64 KiB, ordered by `(client_route_id, created_at)`. The query uses the same fixed
threshold, preserves its peer filter and existing page limit, and joins only
eligible-size candidates to dispatch state. It no longer sorts small history.
The index is created for existing databases without clearing rows.

Post-fix the identical 10,000-row test records **fewer than 100** VM instructions
and no temporary sort. Its 100-instruction sampling hook prints zero callbacks;
that is **not zero computation or zero milliseconds**. These are deliberately
schema-only synthetic rows, not authenticated messages or model workload proof.
The test also checks peer separation, oldest-first order, threshold boundaries,
page bounds and index creation without deleting existing records.

No receipt semantics, body quota, retained proof, artifact byte, encryption,
message retry or UI behavior changed in this follow-up.

## Real Native Small-Message Check

Both runs use the documented [native latency method](MQTT_NATIVE_LATENCY_20260913.md):
two isolated real Signal/Python/SQLite endpoints, three owned loopback TLS
listeners, 30 measured messages per strategy, seed `20260915`, six excluded
warm-ups, and 66 checked business records per run. No concurrent build/load test
was run during either latency measurement. Unrelated host activity is not
controlled. The first run used commit `2a66445c5`; the second included this index.

Nearest-rank percentiles in milliseconds, measured to authenticated durable
receipt commit, not broker PUBACK or controller polling:

| Run | Strategy | n | Request p50 | Request p95 | Publish to receipt p95 | Submitted frames |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Before index | Single available path | 30 | 850.98 | 1692.35 | 1520.93 | 30 |
| Before index | Automatic multi-path | 30 | 965.91 | 1556.88 | 1336.13 | 30 |
| After index | Single available path | 30 | 989.60 | 1335.92 | 1166.14 | 30 |
| After index | Automatic multi-path | 30 | 898.61 | 1303.72 | 1183.59 | 30 |

All four cohorts submitted 658,020 counted business MQTT bytes each, without
redundant business frames. The predeclared within-run multi/single p95 ratio
budget remains 1.10; observed ratios 0.920 and 0.976 both passed. This does not
establish that the index caused the observed cross-run timing differences: the
native workload has only 66 messages, not a 10,000-row seeded inbox, and host
timing varies. The VM-work regression is the direct evidence for the query fix.

Initial authenticated-ready observations (one per endpoint, not percentiles)
were 839.91/339.59ms before and 438.13/267.85ms after. Native JVM and identity
startup are excluded from that clock. No cold-start p95 is inferred.

Reports:
- `build/mqtt-native-latency-compaction-v1/report.json`
- `build/mqtt-native-latency-compaction-index-v1/report.json`

## Regression And Limits

- **339 expanded Python tests passed**, 26.358s, including the **72 focused**
  receive/dispatch/query tests. Overlapping selections are not added together.
- Desktop **37 checks** and structure check passed.
- Post-index native PNG and H.264/AAC tests passed with exact original/streamed
  hashes, decoded media and one available contact attachment per case.
  `build/mqtt-native-attachments-index-v1/report.json` has no native/cleanup
  errors. Controller completion was 4.359s and 4.718s, not a latency percentile.
- The earlier 5/21/32 MiB and process/path-loss passes remain evidence for the
  preceding compaction implementation, not newly repeated large-file samples.

These checks do not prove public-provider/Android performance, all-path cold
start distributions, large-attachment performance, App/App delivery, ten real
windows/model tasks, background lifecycle, battery or UI open/save acceptance.
The spec's complete release gate remains unevaluated. The source-only Desktop
change was not packaged into the running production instance; no APK was rebuilt
or installed, and no phone was operated. PR #3045 remains draft.
