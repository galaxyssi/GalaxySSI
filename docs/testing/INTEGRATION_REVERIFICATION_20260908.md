# Integration Reverification Acceptance: 2026-09-08

Desktop source version: 1.1.5. Android and iOS are unchanged. No device install,
production Desktop replacement or persistent scheduler enablement was performed.

## Actual Published Candidate

The verification used the existing isolated campaign state, not a newly invented
successful fixture:

- Campaign: `campaign-goal-d3239cfaeafc0a91863cc804aec3cd10`.
- Task: `evolve-dag-5ecc630326a3a1cd25a2c4699f011cd1`.
- PR: [#2892](https://github.com/galaxyssi/GalaxySSI/pull/2892).
- Accepted source: `b9edb79574d80c55c601696901073fd99777a905`.
- Accepted candidate: `013a98b5a5d2ff2aeb26bea465ee5cc283f4f6d0`.
- PR merge: `516778576ed1c2ff1b2bda127856a1de151efbec`.
- Independently verified integration: `fb7f5b0e80dbbbfc87376148e745a94d74a0c0d7`.

The production CI supervisor re-indexed the previously terminal failed watch,
read actual GitHub metadata, fetched the exact main commit's Git objects,
verified ancestry and the one unchanged candidate path, and read the integration
commit's CI checks. All five reported checks passed: repository guard, Android
build, Desktop source smoke, core regressions and Windows packaging.

The immutable integration CI fingerprint was
`f6936276cafe3dd59d8898814ae176b2e765995af5701b1b2ffdaa0d7a675f38`.
The retained-path proof fingerprint was
`91bbc3d118c7a2e107f0cde83080826443d92c0227c34021002be0ccf93278b7`.
The original PR's failed CI remained in `snapshot`; the separate `integration`
evidence let `published_outcome` return a completed dependency with
`historical_ci_failed=true`. The candidate attempt count did not increase. No
model, implementation, commit, push, or PR publication was repeated.

The actual campaign still contains another pending node. This test deliberately
did not dispatch it or claim that the original multi-node goal was complete.
The local report and harness are retained under this worktree's ignored `build/`
directory as `integrated-campaign-evidence.json` and
`verify_integrated_campaign.py`.

## Regression Scope

The combined CI, integration, campaign, replanning and repair suite passed 138
tests in 93.131 seconds. Desktop's 29 JavaScript tests and source structure check
passed. The repository guard passed, including the Chinese text policy check.

Real temporary Git repositories cover unchanged additions and deletions, later
candidate modification, restored deleted files, renamed files, executable mode
changes, unrelated ancestry, dirty-checkout preservation and 1,004 changed paths
verified using two tree diffs rather than per-file subprocesses. GitHub transport
responses are controlled in these unit tests; the live acceptance above uses
actual GitHub responses.

Durable tests cover failed publication recovery, paused campaigns, interruption
between retry and claim, and missing publication records. Recovery never
recreates the published task's implementation. CI tests cover terminal-watch
reopening, unavailable evidence, successful stop conditions, and the unchanged
normal open-PR repair path. A bare `passed` flag cannot stand in for a complete
identity-bound integration proof.

## Remaining Work

This proves integration of retained candidate bytes, not semantic equivalence
when candidate files have subsequently changed. Such changes require a fresh
model-led acceptance decision. It does not prove that every inherited CI failure
can be automatically repaired, that all required-check policies are configured,
or that the entire long-running campaign has passed final goal acceptance.
