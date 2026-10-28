# Research Compaction and Recovery

## Failure Mode

The observed long research runs entered Codex context compaction near their
258,400-token model window. The provider continued emitting compaction heartbeats,
but those nested provider events were not forwarded by the installed app-server.
The host consequently applied its ordinary 180-second no-output watchdog to an
active compaction. Retrying with only the original question discarded prior work.

## Runtime Contract

- Ordinary silence remains bounded at 180 seconds. Compaction starts only from an
  observed, turn-scoped `contextCompaction` item, not from high token usage alone.
- Nonempty reasoning `summaryTextDelta`/`textDelta` events count as progress, just
  like assistant deltas. Provider status/keepalive events do not reset this clock.
- A scoped app-server `error` with `willRetry=true` starts a separate 120-second
  recovery window. Repeated errors do not renew it or borrow compaction time.
  Fresh model output clears it; `willRetry=false` fails without waiting for silence.
  The actual provider error is retained, not replaced with a generic API failure.
- At the ordinary silence boundary, read the exact turn before interrupting it.
  Reconcile a missed terminal result or compaction start; an `active` status alone
  is not evidence of new progress. The final status RPC may add up to 10 seconds.
- During compaction the watchdog reads the exact provider thread/turn every 30
  seconds, with a 10-second RPC timeout. A matching terminal snapshot reconciles
  a missed completion instead of restarting the task.
- Compaction has an independent 300-second deadline. Status probes and duplicate
  starts cannot renew it. Its original start is retained in the existing execution
  checkpoint across host restart. Failures report `codex_compaction_timeout`.
- At 65% of the *last input* context window, a research turn gets at most one
  checkpoint/synthesis request. It does not reset the silence clock. Cumulative
  token usage is not a context-pressure measurement.
- The integration does not read private Codex logs or hidden reasoning in production.

## Research Handoff

`research_checkpoint` upserts stable goal, finding and gap entries. Source URLs and
executed queries are also recorded from tool observations; `research_audit` records
are mirrored with their provenance. Records are individually encrypted in SQLite,
deduplicated and paginated. Full tool observations remain in the existing evidence
ledger; the checkpoint is a bounded index/summary, not a replacement for sources.

Observed quotations establish provenance, not semantic truth. Model-reported
findings without observed passages remain explicitly unverified. All checkpoint
content is untrusted data, not instructions.

Fresh retries receive original goals plus a bounded priority projection of saved
findings, gaps and sources. Additional records are available through paginated
checkpoint reads. The Android authenticated outcome path stores incremental records
under the exact conversation/turn; stale revisions cannot overwrite newer records,
and deleted conversations reject late updates. Provider failover uses that same
handoff, including when changing from Codex to a cloud model. A new turn does not
inherit an earlier turn's recovery marker.

Transport splits checkpoint updates by UTF-8 byte size, below the existing 16 KiB
task-event metadata ceiling, and at most 24 entries per packet. Terminal replies,
offline result archives and explicit recovery snapshots include bounded canonical
checkpoint packets, independently of coalesced progress and the event history cap.
An encrypted task-to-scope binding prevents another task from retrieving them.
Fresh retries refresh a valid trailing phone projection from canonical findings,
instead of skipping local evidence merely because a recovery marker is present.
Checkpoint records are not rendered as chat narration.
The recovery prompt never asserts completeness when its projection is partial.

Native search defaults to short output in the research policy, with longer passages
requested only as needed. Exact duplicate host search/fetch responses are replaced
by a reference to their earlier evidence. The host cannot rewrite the provider's
native web history or guarantee a provider compaction will finish. Source failures
remain explicit gaps; they do not require restarting successful queries or blocking
delivery of the supported findings.

## Verification

Backend regression tests cover phase deadlines, late/missing terminal events,
foreign thread/turn rejection, restart deadline persistence, context-pressure
measurement, fresh-thread evidence handoff, encryption, pagination, duplicate
updates, uncertain claims and UTF-8 transport limits. Android tests cover recovery
projection and malformed inputs; the device test additionally covers persisted
revision ordering, turn isolation and deletion tombstones. Real provider latency
and the complete original university-search run require separate live acceptance.

The first live retest did not pass: it did not enter compaction; the provider's
sampling connection repeatedly timed out. It also exposed short packets containing
more than 24 entries and facts lost by progress coalescing. These are covered by
the terminal checkpoint and retry-projection regressions, not classified as a
successful end-to-end run.

## Codex Reference and Product Policy

The [Codex configuration reference](https://developers.openai.com/codex/config-reference)
documents an SSE idle default of 300,000 ms, HTTP request retries of 4 and stream
interruption retries of 5. These are transport settings, not a total task deadline.
The [app-server protocol](https://learn.chatgpt.com/docs/app-server) exposes separate
compaction, error and turn-completion lifecycles. GalaxySSI's 120/180/300-second
budgets above are explicit host policies, not claims about Codex Desktop defaults.
Useful work has no three-minute total duration limit; only Auto may switch providers.
