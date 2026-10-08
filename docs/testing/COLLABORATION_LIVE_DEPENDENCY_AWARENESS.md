# Coordinator dependency awareness

An existing review assignment is not proof that a review has started. The incremental coordinator's compact work inventory now includes host-observed status, stage, dependency policy, exact pending dependency IDs/statuses, unsuccessful dependencies, review subjects, and pinned milestone tokens.

- `RUNNING` and `QUEUED` come from the host execution snapshot.
- A scheduler-committed result takes precedence over an older status observation.
- `RESULT_PENDING` means a terminal status was observed but the coordinator's scheduler checkpoint does not yet contain the result. It does not release dependencies.
- `unobserved` is unknown, not presumed running or completed.
- Dependency state is separate from execution status: satisfied dependencies can still be queued for capacity; failed dependencies block success-policy work but may be inputs to terminal-policy diagnostics.
- The inventory remains a bounded, dispatch-time metadata snapshot. Truncated assignments and omitted work are explicit. It contains no peer outputs or implicit read grants.

The coordinator can choose a distinct, exact-version interim check using the existing `uses_milestones` mechanism. Existing assignments remain immutable, independent exploration remains isolated, and a publication is not automatically verified. This change does not cancel work, bypass dependencies, change concurrency, or prescribe an experimental strategy.

## Verification

`CollaborationLiveInventoryTest` covers queued reviews, dependency failures, terminal-policy diagnostics, uncommitted terminal observations, stale status, review subject separation, milestone identity, and bounded unknown-state reporting. `AgentTeamLiveGraphIntegrationTest` verifies that the production runtime supplies a real running-member observation while another result has completed.

Existing live-graph and milestone suites retain coverage for durable expansion, replay, exact-version access, independent authorship, and no repeated execution. Synthetic checks establish the information contract, not that a model will necessarily choose a better plan. A fresh bounded real-model replication is required before claiming improved coordination or team capability.

## Local validation, 2026-10-08

- Android v1.4.95 / 1180: debug APK and instrumentation APK assembled successfully.
- 67 focused unit tests passed across inventory, live graph, runtime integration, milestones, and research prompts.
- S20U (SM-G9880): eight local instrumentation tests passed, including production inventory status, publication-triggered coordination under saturated workers, missed-wakeup recovery, immutable retry, pause/revocation, and independent-reader isolation.
- Repository checks and diff whitespace checks passed. No additional real model requests were made for this increment's device tests.
