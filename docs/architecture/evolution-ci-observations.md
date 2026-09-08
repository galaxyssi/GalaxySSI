# Local CI Repair Observations

Desktop 1.1.4 gives the local self-evolution repair Agent two additional
read-only tools. An empty GitHub Actions check summary is no longer its only
source of diagnostic evidence.

- `ci_checks` lists failed checks for the host-bound PR and commit. It returns
  up to 20 checks per page, with an explicit cursor. Names and summaries are
  bounded, and shortened summaries are marked as truncated.
- `ci_log` reads a failed GitHub Actions job. It starts at the log tail by
  default and returns 4,096-character pages with backward and forward offsets.
  The model chooses what to inspect and how to diagnose the failure.

Only the default local adapter for a task with a host-owned CI repair target
receives this capability. Normal task schemas do not advertise CI tools.
External CLI adapters are unchanged by this increment. The CI repair task
prompt carries a small failed-check index, not the entire CI output. Logs enter
the model as tool observations, not as authoritative instructions or source
editing commands. Host gates and acceptance remain independent.

## Identity And Recovery

Each operation verifies the PR repository, branch, commit, and lifecycle. Log
download additionally verifies the job's run ID, commit, completion state, and
check-run identity through GitHub's API. URLs supplied by the model are not
accepted, and arbitrary provider URLs are never followed.

The open repair target is checked again after downloading the log. A changed,
closed, or merged target invalidates the observation and clears its cached log.
Repair must use a new host-owned target rather than silently editing a different
head. Other CI providers return an explicit unavailable-provider observation.

For post-merge diagnosis, the read-only validation harness can deliberately
bind a new immutable lifecycle snapshot, including the merge commit. Its file
scope is empty. This does not let an existing repair task continue across a
merge, and cannot change the repair's bound repository, branch, or head.

## Data Lifetime

Typed provider context-window errors trigger removal of the oldest complete
action/observation pair, followed by another inference request. The original
system contract, user goal, and latest observation remain intact. No tool was
executed on the rejected request, so recovery does not repeat a completed write.
If the goal and latest observation alone cannot fit, the precise error remains
visible instead of silently dropping the goal. Ordinary HTTP failures do not
trigger this path, and cancellation is checked before retrying. The durable
compaction event contains counts, not discarded observation content.

Only one redacted job log is cached in the task-local tool instance. A job
identity or completion revision change causes a new read. Persistent action
events record the operation and outcome, not the log content. No log file is
created by the runtime tools.

The dedicated diagnostic subprocess reader bounds capture before allocating
arbitrary process output, retains at most 2 MiB, and marks incomplete logs
explicitly. This is an evidence-envelope bound, not an Agent action budget or a
task lifetime limit. A 120-second fetch timeout becomes an observation; it does
not grant acceptance. Windows child ownership is retained and temporary byte
buffers are cleared. A truncated log must not be treated as complete evidence.

## Validation

`tools/testing/run_ci_log_acceptance.py` reads actual GitHub observations using
the authenticated host CLI. With `--endpoint` and `--model`, it runs the same
read-only tool loop through a literal-loopback local model. It exits nonzero if
no successful log observation occurred. It never publishes, merges, or grants
candidate acceptance.

See the [live verification report](../testing/LOCAL_CI_OBSERVATIONS_20260908.md)
for actual GitHub evidence, local model results, context recovery, and the
remaining full-loop acceptance boundary.

```text
python tools/testing/run_ci_log_acceptance.py --pr https://github.com/owner/project/pull/7 --output build/ci-log-evidence.json
python tools/testing/run_ci_log_acceptance.py --pr https://github.com/owner/project/pull/7 --output build/ci-model-evidence.json --endpoint http://127.0.0.1:18572/v1/chat/completions --model local-model
```

This increment delivers diagnostic capability, not a claim that every CI
failure can be repaired inside the original candidate scope. Scope conflicts,
post-merge repair planning, CI success, and integrated-goal acceptance remain
separate decisions and verification milestones.
