# Thread Usage Reconciliation

Model-free, read-only collection of Codex's **estimated thread usage**, bound to
existing private GalaxySSI trial captures. This does not invoke or resume a task,
change the running Desktop, query account-wide totals, or alter model selection.

```powershell
python -B tools/testing/codex-usage/thread_usage.py `
  --codex C:/path/to/codex.exe `
  --capture C:/private/experiment/capture.json `
  --output C:/private/experiment/thread-usage-observation
```

Repeat `--capture` for multiple frozen captures. The existing capture auditor
validates hashes, journal sequence and task identities before any RPC. Each
unique provider thread is read once, even when several tasks share it. No retry
or account-level fallback is performed. Output must be a new directory outside
Git, without symlink/junction ancestors. Do not commit real captures or reports.

The short-lived client only permits initialization and
`account/usage/read` with exactly one explicit `threadId`. It closes its own
process, never the application's Desktop process. One failed query is retained
and does not discard the other observations. Raw provider errors, account
summaries and daily buckets are not saved; response hashes and bounded error
codes are retained.

## Interpretation

The installed app-server schema exposes `threadUsage`, with estimated credits,
optional estimated USD micros and groups by reported model, reasoning effort
and speed. These fields are estimates, not invoices or per-response receipts.
Missing optional counters remain unknown. Cached input is a subset of input;
it is not added to total tokens. `netNewInputTokens` is retained separately,
without assuming it means input minus cached input. Empty/ambiguous groups,
identity mismatches and inconsistent counters are not aggregated.

The report compares the four common counters against the last captured
cumulative notification endpoint. A match corroborates those two observations;
it does **not** prove zero pre-trial history, complete final coverage, exact trial
cost, actual served models, request counts, or equal budgets. Shared threads are
not attributed to one trial. `trial_token_total`, `billed_cost` and
`provider_request_count` therefore remain null, and
`ready_for_equal_budget_comparison` remains false.

Exit 0 means estimates were returned, not that the experiment passed a budget
gate. Exit 2 retains unavailable/error observations. Exit 1 indicates invalid
inputs. Use prospective before/after evidence and explicit ownership/coverage
contracts before treating estimates as attributable trial resources.

The [official app-server documentation](https://learn.chatgpt.com/docs/app-server)
describes usage notifications and `account/usage/read`. Thread-specific fields
must be checked against the installed CLI's generated JSON schema; older
versions or unavailable billing routes may return null or an RPC error.

```powershell
python -B -m unittest discover -s tools/testing/codex-usage -p test_thread_usage.py -v
```

Tests use synthetic captures and stubbed clients; they make no network or model
requests. This tooling does not require an Android/Desktop version bump.
