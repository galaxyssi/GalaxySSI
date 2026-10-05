# Remote Codex Trial Capture

This local, read-only collector joins an explicitly declared Android trial to
Desktop's original task and provider-usage journals. It starts no model, runtime,
network connection, task, retry or recovery. Ordinary app behavior is unchanged.
Private scopes and captures must remain outside Git repositories.

## Why a Separate Capture

Android's cloud model-call ledger covers direct cloud requests only. An empty
cloud export does not mean a Desktop Codex trial used zero model calls or tokens.
One Desktop task can contain several provider turns, tools and internal requests.
Usage notifications are not unique HTTP request receipts, and cumulative thread
totals must not be summed as per-task totals.

## Scope and Invocation

Create a private JSON file using the actual phone-owned route, conversation,
turn, paired contact and the original planned assignment node IDs:

```json
{
  "format": "galaxyssi.codex-trial-scope.v1",
  "trial_id": "operator-declared-trial",
  "client_route_id": "exact-phone-route",
  "conversation_id": "exact-phone-conversation",
  "turn_id": "exact-phone-turn",
  "contact_id": "exact-paired-codex-contact",
  "agent_id": "codex",
  "requested_model": "gpt-6-astra",
  "requested_reasoning_effort": "xhigh",
  "expected_nodes": ["author", "review", "deliver"]
}
```

Do not invent these identities or obtain expected nodes by dropping failed or
unstarted assignments. The scope is an operator declaration, not independent
proof that the original protocol was followed. Keep its hash and original plan.
Model and effort must be explicit; automatic values are rejected.

From `apps/desktop/core/galaxyssi-link/backend`, with Desktop's configured Python:

```powershell
python -m codex_trial_capture --database C:/Private/agent-run-events-v1.sqlite3 --scope C:/Private/trial-scope.json --output C:/Private/trial-capture.json
```

The actual Desktop database must retain its existing encryption key. Never copy
or upload that key. The collector opens SQLite read-only, does not construct a
runtime manager, and reuses the authenticated usage journal reader. Output paths
are resolved before checking Git ancestors, including worktree `.git` files.
Existing captures are never overwritten. Compare later exports as new snapshots.

Exit 0 means a scoped capture was written without the listed structural issues,
not that the answer was correct. Exit 2 preserves a capture with missing nodes,
nonterminal work, drift, unobserved generations or other explicit issues. Exit 1
means malformed scope, corrupt evidence, a missing database or an export error;
no model is started in any case.

## What Is Preserved

- Every matching task, including failed/cancelled/timed-out tasks, duplicate
  assignments and unexpected node IDs. No best-of selection or hidden retries.
- Every observed execution generation, with journal pagination and per-journal
  upper sequence watermarks. Unobserved generations remain explicitly unmeasured;
  sparse generation IDs do not cause enumeration of fabricated empty history.
- Planned nodes without matching task records, labelled `unobserved`, not
  assumed unattempted. Phone dispatch evidence is required to distinguish them.
- Requested model and effort from task request snapshots and usage observations;
  disagreement is a control-drift issue, never silently normalized.
- Lifecycle timestamps and source revisions. Task snapshots read before and
  after collection detect concurrent lifecycle/revision changes.
- Start, usage and terminal coverage for each observed provider thread/turn.
  An earlier completed turn cannot conceal a later unfinished turn.

Prompts, final answers, attachments, pairing secrets and credentials are excluded
from this capture. Obtain outcome and phone-delivery evidence separately, using
the same exact trial identity. Current task timestamps describe the stored task,
not a reconstruction of timestamps for each historical execution generation.

## Interpretation Limits

`request_count`, `trial_token_total`, `billed_cost`, `actual_model` and
`actual_reasoning_effort` remain null. The captured requested settings cannot
prove what the provider served. Raw cumulative token snapshots are retained but
not summed. Late or unobserved provider events may be missing even when all local
journal pages were read; `provider_history_complete` remains false.

`ready_for_equal_budget_comparison` is always false. This collector does not
enforce budgets, attest isolation, externally grade answers, establish Android
delivery or implement the six-arm longitudinal runner. It closes the remote
capture gap without pretending a small integration trial proves efficacy or
fair cost. Original private data and manuscripts must not enter PRs.

## Local Regression

```powershell
python -m unittest test_codex_trial_capture test_codex_usage_export test_agent_provider_usage test_codex_provider_usage -v
```

The tests use synthetic isolated databases. They cover exact identity isolation,
missing/failed/running and duplicate assignments, historical/sparse generations,
control drift, corruption, concurrent snapshot changes, per-turn coverage, unknown accounting,
read-only database behavior and private, non-overwriting export.
