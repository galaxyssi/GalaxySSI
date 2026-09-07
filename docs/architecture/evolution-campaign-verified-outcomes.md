# Verified campaign dependencies

## Problem

Publishing a PR does not put its changes on the execution base. Completing a DAG
node at publication allowed dependent tasks to fetch `main` without the code they
depended on. A green PR also does not prove that it was merged, or that a later
checkout still contains its integration commit.

## Completion evidence

The campaign adapter consumes the CI observer's persisted, head-bound snapshots.
It does not perform network requests from campaign reads or UI rendering.

- Published tasks remain running internally, with `awaiting_ci` or
  `awaiting_integration` observations exposed on the campaign node.
- Failed CI with an active repair stays observable, not permanently failed.
- A PR closed without merging fails its node with the actual reason.
- A merged candidate with completed failing checks fails verification. No attempt
  is made to push a repair into a closed PR; the coordinator must replan.
- Successful completion requires the matching PR URL, verified checks, a merged
  lifecycle, and a valid integration commit on the current `main` execution base.
- Before a dependent production worker starts, the manager checks every published
  direct and transitive dependency's integration commit with `git merge-base --is-ancestor`
  against the exact pinned source. A stale/replaced base cannot silently proceed.

The adapter does not merge PRs automatically or change repository protection.
This matches the current executor's main-based source policy. Isolated candidate
composition without upstream merges remains a separate Coordinator capability.

The generic DAG reducer remains provider- and project-independent. Its evolution
adapter receives the published-outcome resolver explicitly. A missing resolver
does not turn an unverified publication into success. Non-published local task
completion retains its existing semantics.

## Recovery and observation

Identical waiting observations do not append repeated checkpoints. Waiting state
survives reconstruction, and unrelated ready nodes can continue. The CI observer
now checks merged PR heads too; merged PRs with pending or absent check evidence
remain observable. Previously stopped merged watches without integration metadata
are scheduled for a fresh observation when indexed after an upgrade.

Finishing a campaign rechecks its published tasks against persisted CI evidence,
including nodes completed by older code. Evidence is the latest **observed**
snapshot, not a synchronous freshness guarantee. The coordinator still owns final
goal acceptance and explicit `finish` evidence; this is not an automatic claim
that an arbitrary user goal has been achieved.

## Validation

Tests cover pending/failed/repaired/merged/closed outcomes, missing or wrong PR
identity, observation errors, integration commits, waiting checkpoint deduplication,
restart, independent node progress, and final-verification refusal. Real local Git
repositories verify that exact/later bases contain dependencies and older bases
are rejected. No provider, phone data, or shared Desktop process is changed by
these tests.

Local verification: 168 evolution tests passed, including 23 additional cases
relative to the integrated DAG/CI baseline. A separate 45-test selection covering
campaign outcomes and the generic DAG reducer also passed, as did repository
checks. These selections overlap and must not be added as distinct coverage.

On 2026-09-07 a read-only live observation of merged PR #2851 returned 14 passed
checks at head `8f9b659aa3eda7d2c0088e72ed1f3f7473a2af74` and integration commit
`894fd16002a44eef7a6ace533d10f6c2aeacae95`. This validates the merged-head API path,
not the entire long-running goal or S20U runtime acceptance.
