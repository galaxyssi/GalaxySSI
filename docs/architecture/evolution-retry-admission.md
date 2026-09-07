# Evolution child retry admission

A long-running goal has no total action or plan-revision budget. Individual
legacy child tasks still have a configured candidate-attempt budget. Previously,
a planner could repeatedly retry a child whose attempts were exhausted. The host
would enter preparation and immediately fail without executing any new action.

Terminal child observations now include the original error code, attempt count,
remaining attempts, `retryable`, and a stable `retry_blocker`. The local planner
can distinguish a retryable transient failure from `child_attempts_exhausted`.
It decides whether to replace the failed child or wait. The host does not reset
attempt history, fabricate a new goal, or automatically replace model decisions.

Model retry admission re-reads the actual child before changing the DAG, so a
stale graph cannot admit a child that has since exhausted its attempts. Persisted
or manually submitted retry operations are also checked immediately before
dispatch. Exhausted recovered `proposed` children produce a failed-node
observation rather than starting an empty worker. Existing durable command
idempotency is preserved.

The existing explicit replacement operation assigns a fresh child identity while
preserving the parent objective, dependencies, and retired-node history. It does
not count as successful execution or allow dependents to run before validation.
Fresh work remains subject to the normal local tools, host gates, review,
publication, CI observation, and integration checks.

Tests cover exhausted dispatch after ledger reopen, stale planning evidence,
model validation feedback across restart, explicit replacement with dependencies,
and interrupted proposed children. Live local-provider acceptance remains a
separate requirement; fixture tests do not prove model competence or delivery.
