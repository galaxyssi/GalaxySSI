# Adaptive research and honest source disclosure

## Scope

The shared Android/Desktop research quality contract now requires subquestion-driven,
multilingual research where useful, original-body reading, claim/passage attribution,
contradiction checks and thematic synthesis. Native remote agents own their research
loop; GalaxySSI does not launch a duplicate search loop around Codex.

The objective is depth, accuracy and coverage, not a minimum number of URLs.
Simple lookups retain their focused fast path. Source failure is not task failure.

## Android execution

- Default active-time ceiling: disabled (`active_minutes=0`). An explicit 1-1440 minute
  limit remains supported. Cancellation and no-progress convergence are retained.
- Default tool/model ceilings: 512 calls / 256 rounds; configurable up to 4096 / 2048.
- Default single tool/model timeout: 180 seconds. Individual sites still have shorter
  bounded request deadlines; a hanging site must not consume an unlimited task.
- Default evidence observation allowance: 8 million characters, configurable to 32 million.
- Research calls accept up to 100 planned queries, 64 target bodies per batch, six
  concurrent page readers and per-host throttling. Defaults: 24 bodies, 120 seconds
  overall, with up to 60 seconds reserved for reading. Early count-based completion
  is off by default. Unexecuted queries remain explicit retrieval gaps.
- `web_fetch` supports `offset`, `length` (256-8000 characters), and
  `document_sha256`. Its reading window reports offsets, continuation, version change
  and scope. Windows refer to extracted readable text, not every byte of the source.
- Deliberate reading windows survive ordinary prompt excerpt compression. New windows
  count as progress and cannot be replaced by a cached response for another window.
- The existing encrypted Run Kernel observations remain the recovery authority;
  checkpoint capacity matches the maximum configured tool count.
- Before an initial deep-research draft is delivered, snippet-only citations trigger
  one bounded body-reading review while tools remain available. This is a retrieval
  completeness check, not an independent semantic judge.
- Anthropic/Gemini conversational output uses the existing configured output allowance
  (4096 tokens by default) instead of a fixed 1200-token ceiling.

## Disclosure and storage

The summary says `found`, not `referenced`. Each source distinguishes discovered,
body retrieved, remotely reported opening, and failed retrieval. Actual Markdown
citations are marked separately; citation presence does not prove entailment.

Sources are encrypted rows keyed by conversation, turn and URL hash, up to 20,000
per turn. The first UI read loads 50 sources; additional pages load on demand.
Retries merge statuses without duplicating URLs or downgrading fetched bodies.
Conversation deletion removes sources and tombstones late events.

The remote protocol still sends bounded receipts and marks truncated delivery.
Not all native agent internals are observable. The app must never infer complete
reading or verification from a completed native `openPage` event.

## Verification

- Unit fixtures: sequential long-body coverage, version change, context projection,
  reading budget reservation, multilingual plans, source states, no-progress detection,
  explicit time limits, citation parsing, and encrypted checkpoint regression tests.
- Desktop fixtures: shared prompt routes and source receipt replay/delivery semantics.
- Android instrumentation: 10,000 synthetic sources, duplicate ingestion, bounded page
  reads, status update, turn isolation and deletion; disclosure expand/collapse tests.

## Limits and quality acceptance

### Verified build

- Android 1.2.10 (1015): debug app and instrumentation APKs built successfully.
- Android focused and regression unit tests: 124 passed, zero failed or skipped.
- Desktop research, routing, recovery and terminal-outcome tests: 89 passed.
- S26U (SM-S9480): overlay installation and seven instrumentation tests passed
  in 75.609 seconds, including the 10,000-source synthetic corpus, disclosure UI,
  source navigation, history restoration and delivery isolation. Dedicated test
  records were cleaned up without clearing user application data.
- No real large-scale web research request was issued for this acceptance run.
- Desktop contract changes are tested in source; the running Desktop instance was
  not restarted or redeployed in this acceptance run.

A 10,000-source storage fixture is NOT a 10,000-document research-quality benchmark.
This change does not promise exhaustive web coverage, full PDF/media comprehension,
independent semantic verification, or unlimited context. The local body cache retains
its bounded eviction policy. Large investigations still need hierarchical, evaluated
claim summaries and persistent research artifacts beyond merely increasing tool limits.

Before claiming stronger research quality, run the same multilingual complex tasks on
DeepSeek and remote Codex. Score subquestion coverage, decisive-body access, source
independence, citation entailment, contradiction handling, temporal/entity correctness,
useful synthesis and honest unknowns, with human review and repeated runs. Record
latency and cost separately; source count is not the quality score.
