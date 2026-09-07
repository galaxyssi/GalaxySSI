# Live campaign acceptance milestones

The opt-in `tools/testing/run_local_campaign_acceptance.py` must distinguish
intermediate progress from completion. It reads the current durable graph and
current child tasks on every observation. Saved `candidate_ready` and
`needs_observation` flags are invalidated at controller startup. Retired tasks and
the manifest's historical `published` audit list cannot terminate a new run.

The campaign loop reports these exit codes:

| Code | Stage | Meaning |
| --- | --- | --- |
| 0 | completed | Nonempty current DAG completed, no missing child or active worker, and current PR integration outcomes verified |
| 1 | completion_unverified | A terminal graph lacks the required completion evidence |
| 2 | candidate_ready | Current candidate awaits explicit publication; not end-to-end success |
| 3 | awaiting_integration / published | Current PR published, but complete integration not established |
| 4 | needs_observation | Planner needs further observation or a local model is unavailable |

Running work has no terminal exit code. A current candidate does not terminate
the controller while another implementation worker is active. Publishing one
child cannot mask another current running or missing child. Successful
`--publish-task` returns 3, not 0. Inspection, recovery-only, and revalidation
commands retain their operation-specific exit status and never claim campaign
completion.

The full campaign field remains false until current graph and integration
evidence establish completion. This is evidence for that selected campaign, not
proof of the full GalaxySSI product goal, model quality, or phone acceptance.

## Regression and real-model evidence

The bug was observed in a real local campaign: a superseded candidate left
`candidate_ready=true` in the manifest while the current replacement child was
still running. The old harness could also exit 0 merely because an earlier PR
was present in its audit history. Regression tests cover restarts, retired nodes,
unresolved observations, missing children, active workers, publication, and
verified integration separately. No live task, goal, candidate file, or ledger
is rewritten to manufacture a successful result.
