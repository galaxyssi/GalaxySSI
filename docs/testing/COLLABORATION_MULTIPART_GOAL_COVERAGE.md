# Multipart original-goal coverage

Android 1.4.27 extends the existing program-owned acceptance check. A long
original goal no longer needs one author and one reviewer to publish a single
large mapping. Members can work on non-overlapping source-ID assignments, with
independent reviews of each exact saved mapping version.

## Contract

The existing single `goal_coverage: {mapping, review}` form remains valid. A
coordinator can instead return:

```json
{
  "goal_coverage": {
    "parts": [
      {"mapping": {"object_id": "...", "revision": 1, "sha256": "..."},
       "review": {"object_id": "...", "revision": 1, "sha256": "..."}}
    ]
  }
}
```

Every part binds the same hash of the complete original goal and the same
preserved criteria, including their verification constraints. Each part maps
only its assigned host source IDs, with an explicit independent judgment for
every mapped ID. The program checks the union: all source IDs exactly once,
all criteria at least once. Missing constraints, overlapping assignments,
unknown IDs, mismatched local reviews and stale references cannot pass.

Reviewers must differ from the evaluating coordinator and all contributors to
the mapping they review. Unselected current dissent still blocks acceptance;
selecting another positive review does not hide it. Existing original-evidence
read coverage, immutable publications and qualified-validation checks remain
unchanged.

## Saved directories

For many parts, members publish an ordinary versioned workspace artifact whose
body contains `semantic_goal_manifest`:

```json
{
  "semantic_goal_manifest": {
    "format": "galaxyssi.semantic-goal-manifest.v1",
    "goal_sha256": "complete host goal hash",
    "criteria_sha256": "complete host criteria hash",
    "parts": [{"mapping": {}, "review": {}}]
  }
}
```

The empty objects above stand for exact saved references, not inline claims.
Every referenced mapping and review must also be preserved in the artifact's
`parents`. A branch uses `manifests: [exact child references]` instead of
`parts`, with every child likewise in `parents`. Mixing both forms is rejected.
The final assessment contains only `goal_coverage: {manifest: exact root ref}`.

Resolution walks saved directories iteratively, checks original-goal/criteria
bindings at every level, and rejects cycles, repeated branches and duplicate
mapping references. No fixed total source, part or directory-depth count is
introduced. This does not imply infinite memory or unlimited provider context;
authors should publish small batches and compose them through directories.

Directories are rechecked after taking the acceptance review snapshot. The
existing mutation fence then rejects concurrent publication or removal during
verification. This also closes the interval between initial directory
resolution and snapshot creation: an old root cannot certify an updated tree.

## Scope and limits

- The protocol works through the shared workspace/publication and acceptance
  path used by cloud and remote members; it does not start another model loop.
- This phase adds no UI, heartbeat, periodic messages or execution side effects.
  Ordinary chat and completed historical research are not restarted.
- Directory artifacts and reviews use existing encrypted durable storage,
  permissions and group removal. A summary never replaces the original goal.
- Source-ID completeness and independent review integrity are host-verifiable.
  Correct semantic interpretation remains a reviewer judgment, not proof of
  scientific truth, actual experimentation or multi-agent superiority.
- Model-generated assignments are not guaranteed to be well partitioned on the
  first attempt. Invalid submissions receive the existing continuation/repair
  feedback rather than a false completed status.

## Verification

The automated fixtures cover 4,097 original segments, independent partitions,
missing/overlapping coverage, author independence, stale hashes and versions,
unselected dissent, hierarchical references, missing parent provenance,
4,097 directory levels, cycles, and mutations on both sides of snapshot creation.
The local S26U fixture reopens encrypted storage, checks the three-part tree,
and verifies that group removal revokes it. Store reopening is not a phone
reboot or a provider-outage test.

Real Codex/DeepSeek acceptance of the prior original-source read-coverage gate
and the complete resilience/performance matrix must be reported separately.
Deterministic fixture counts are not real-provider success rates.

## Results: 2026-10-03

- Android main and instrumentation APKs compiled. S26U was upgraded in place
  to **1.4.27 (1112)**, and the installed package version was checked. Existing
  application data was retained; no other phone or watch was operated.
- **31 targeted JVM tests** passed, followed by **739 JVM tests in 57 suites**
  for `Collaboration*` and `Mqtt*`, with zero failures, errors or skips.
- **33 local S26U tests passed in 5.348 seconds**: scoped recall, evidence
  persistence, six acceptance/recovery cases including the new three-part
  directory, and 25 atomic-inbox cases. These tests use dedicated fixtures,
  not actual Codex/DeepSeek responses or the user's research.
- The 153,600-byte Kotlin size policy and `git diff --check` passed. The first
  repository-wide check hit a sandbox read restriction on `.pytest_cache`;
  rerunning with read access reached existing i18n-policy failures in unchanged
  files and ignored local logs. No reported finding names this phase's files.
- This branch incorporates main through merged PR #3347 (`dab9b7a7d`). Desktop
  1.4.2 was kept running and was not replaced; its three MQTT paths reported
  connected/receive-ready and its receive queue was empty during preflight.

The phone continued to report `SCREEN_STATE_OFF` / `mIsShowing=true` after
the user's unlock reply. An unlock request was left pending; no new real-provider
attempt was started behind the secure lock screen. The strict original-read
coverage fixture and live multipart-provider behavior therefore remain
**unverified**, not passing samples. No scientific validation, broad resilience
claim or equal-budget superiority is established by this phase.
