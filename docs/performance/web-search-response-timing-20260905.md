# Web search response timing and deadline regression gates

## Scope

Desktop source version: 1.0.7. Android, iOS, provider selection, source budgets,
MQTT, model settings, and existing user data are unchanged. This change does not
claim that the complete phone-to-model-to-phone latency target is met.

## Problem

Search previously began its elapsed timer after preparation and stopped it before
the final cache write. The reported duration therefore excluded real work on the
response path. Each source health receipt also opened and committed a separate
SQLite transaction.

PR #2807's first backend CI attempt observed 3.172 seconds for a test with a
1-second source budget and a 1.35-second whole-call assertion. An isolated rerun
passed. That observation alone does not establish whether the excess came from
scheduling, storage, or a source. A source deadline is not a measurement of the
entire response, and the two now have separate evidence.

## Response contract

`metadata.elapsed_millis` measures the full successful or failed search response
path, including preparation and final cache persistence. `completed_at_millis`
is updated after cache persistence. `metadata.response_timing` contains:

- `scope`: `search_response`, not an end-to-end agent request.
- `clock`: `perf_counter`, monotonic within this process.
- `elapsed_ms`: total measured time.
- `source_budget_ms`: the original shared source budget, not a total-time promise.
- `phases_ms`: prepare, sources, health_write, rank, learning, result,
  cache_write, and finalize.

The timer is private to each invocation and contains no query, URL, article text,
credentials, or model response. Cache hits receive fresh lookup timings instead
of replaying the previous network duration. The cached record is serialized before
its own write finishes; timing for the current response is finalized afterward.
Request validation exceptions still use the existing error path.

## Persistence

Source health receipts from one response now commit atomically in one transaction.
The single-receipt API delegates to the same path. Empty batches do no I/O, and a
failure in the batch rolls back earlier receipts in that batch.

The database also stores user watch settings, so every connection explicitly uses
`synchronous=FULL` with WAL. This preserves the effective setting observed on
previous runtime connections; it does not trade away durability for speed.
Initialization no longer misleadingly specifies connection-local NORMAL.
[SQLite's synchronous documentation](https://www.sqlite.org/pragma.html#pragma_synchronous)
describes the durability distinction between FULL and NORMAL in WAL mode.

## Deadline gates

The real-thread test blocks a source until explicit release and verifies that the
response returns while that source is still blocked. Its outer wait is only a
test liveness guard, not the performance SLO. A separate controlled-clock test
asserts that waits share a budget (1.00 seconds, then 0.75 seconds after the first
completion) and that executor shutdown does not join unfinished sources.

In-memory mutation verification rejected both intentionally broken variants:

- Restarting the full timeout after each source completion.
- Joining unfinished source workers during executor shutdown.

Both deadline tests passed ten repeated runs each (20 executions). The mutation
probe changed only Python objects in its isolated test process, not production
source files. Existing HTTP timeout/cancellation limitations remain unchanged.

## Verification on 2026-09-05

- 47 web search, timing, and evidence-verification unit tests passed.
- 16 Desktop renderer regressions and Desktop structure checks passed.
- Five real-thread/SQLite fixture runs returned their completed evidence without
  joining the blocked source; all connections reported FULL (`2`).
- Three real-network Chinese queries ran through Bing and DuckDuckGo in fresh
  temporary state, without API credentials or a populated search cache.

| Live query | Full search response | Source phase | Results |
| --- | ---: | ---: | ---: |
| SQLite WAL official documentation (Chinese query) | 2380.589 ms | 2315.763 ms | 5 |
| Today's technology news (Chinese query) | 1690.056 ms | 1594.909 ms | 5 |
| Quantum computing basics (Chinese query) | 1340.525 ms | 1223.641 ms | 5 |

The third query had an empty DuckDuckGo receipt and completed Bing evidence; this
is not counted as evidence that every source returned content. These are three
samples, not P95/P99 evidence or a factual-quality evaluation of the answers.

Fixture total response times were 1170.575, 1072.870, 1430.540, 1633.462, and
1429.507 ms. Source phases remained approximately 1009-1031 ms. The phase report
exposes additional persistence and learning time rather than hiding it behind the
source deadline. These results do not establish an overall speedup: host/storage
load varied, and an overall before/after performance gate is still required.

## Reproduction

From the repository root, with the Desktop Python dependencies available:

```powershell
python -m unittest discover -s apps/desktop/core/galaxyssi-link/backend -p 'test_web*.py' -q
python apps/desktop/scripts/probe-web-search-timing.py --samples 5
python apps/desktop/scripts/probe-web-search-timing.py --live --query 'SQLite WAL official documentation' --timeout 5
npm --prefix apps/desktop run check
```

Live network access is opt-in. The probe prints its temporary report directory
and incremental content-free records, keeping query hashes, receipt statuses,
and timings rather than downloaded article bodies. A live probe exits nonzero
if any query returns no evidence. Fixture results are explicitly labeled
synthetic and must not be presented as live-provider performance.

## Remaining work

Full CI, statistically meaningful performance gates, Android end-to-end search
spans, provider TTFT, and delivery/render spans remain separate acceptance work.
This PR does not resolve unrelated backend CI failures or replace the currently
running Desktop binary merely by updating its source version.
