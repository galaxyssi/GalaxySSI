# Offline Codex trial usage audit

`codex_trial_usage_audit.py` reads previously exported Desktop trial captures.
It does not open a provider connection, read account credentials, invoke a model,
restart Desktop, change an App selection or access a phone. There is no runtime
import or production routing change. Keep real inputs and outputs outside Git.

## Why a separate audit

The [App Server notification API](https://learn.chatgpt.com/docs/app-server)
exposes `thread/tokenUsage/updated` for active-thread usage updates. GalaxySSI's
existing receipt contract records cumulative thread counters and a last-usage
snapshot. These are not unique API-response receipts or billing records.

If one member executes three tasks in a reused provider thread, adding all three
cumulative snapshots counts earlier work repeatedly. Counting snapshots as API
requests is also invalid: repeated notifications, tools, retries, unavailable
events and multiple provider requests can break that correspondence.

## Input and checks

Supply one frozen `galaxyssi.codex-trial-capture.v1` file per trial. The embedded
scope can be node-scoped v1 or source/person-bound v2; the audit consumes the
captured bindings, not task names guessed from model labels.

The tool verifies capture and journal digests, task identity, planned assignment
bindings, generation, contiguous sequence, event identity and counter types.
It retains task/turn observations across failures and retries. It marks missing
tasks, nonterminal tasks, missing generations, incomplete turn markers, changed
controls and malformed counters. A single invalid thread prevents a combined
endpoint sum; the remaining observations remain visible for diagnosis.

Snapshots are ordered by local receipt time and within-execution sequence. An
ambiguous cross-execution timestamp or decreasing cumulative counter prevents
aggregation. The tool does not take a maximum to conceal a reset or an out-of-order
old event. Shared provider threads across supplied trials are exposed and prevent
combined sums. For intentionally persistent longitudinal tasks, inspect this
flag against the assigned persistence condition, rather than assuming every reuse
is an error. This tool does not itself implement a longitudinal accounting window.

The output reports:

- One last observed cumulative endpoint for each provider thread.
- The sum of those endpoints, only if all captured observations pass the checks.
- Input, cached input, output, reasoning output and optional cache-write counters.
- Uncached input as `input - cached_input`, not a monetary estimate.
- Observed task, turn and snapshot counts, separately from unknown request count.
- Explicit issues and the original capture digests.

Cached input is a subset of input. Reasoning output is a subset of output. They
must not be added to the parent counter again. Unknown optional counters remain
null rather than zero. A valid zero reported by the provider remains zero.

## Limits

`observed_thread_cumulative_endpoint_sum` is deliberately **not** named trial cost
or trial token total. It can include pre-trial history and omit late/missing
notifications. A newly named App conversation does not establish a zero provider
baseline. A terminal event does not certify that the final usage event arrived.
`trial_token_total`, `provider_request_count` and `billed_cost` remain null;
`ready_for_equal_budget_comparison` remains false even when there are no issues.

Hashes check local consistency, not independent authenticity. Disjoint thread
IDs do not prove isolation of filesystem, tools, evaluator answers, memory or
provider state. This tool does not verify answer quality, scientific novelty,
causal improvement, actual served model or full-lifetime resource enforcement.

Equal-budget claims need prospectively measured accounting boundaries, complete
request/tool/retry coverage, authoritative cost evidence and enforced allocation.
Do not relabel a fixed dispatch-count or fixed-time comparison as equal compute.

## Run

From `apps/desktop/core/galaxyssi-link/backend`:

```powershell
python codex_trial_usage_audit.py --capture C:\private-trial\single-capture.json --capture C:\private-trial\team-capture.json --output C:\private-trial\usage-audit.json
python -m unittest test_codex_trial_usage_audit test_codex_trial_capture test_codex_usage_export test_codex_provider_usage test_agent_provider_usage
```

The output path must be new and outside every Git repository. Existing reports
are never overwritten. Exit 0 means the observed audit has no detected issues,
not that accounting is complete; exit 2 preserves an issue-bearing audit, while
exit 1 rejects malformed, corrupted or unsafe input/output.

The tests use synthetic records only. Never commit real trial captures, prompts,
answers, reference solutions, private protocols or papers with this tooling.
