# CI Verification Evidence

## Scope

Desktop 1.4.5 separates merge-friendly CI status from explicit reported CI success
used by Evolution campaign dependencies and retained-candidate integration checks.
No GitHub branch protection, merge setting, auto-merge behavior or user approval
policy is changed. Android UI and the provider execution loops are unchanged.

GitHub treats `success`, `skipped` and `neutral` as successful statuses for merge
requirements. GalaxySSI previously mapped all three to `passed` and then used that
aggregate for campaign completion. A skipped or neutral check is not evidence
that the corresponding verification succeeded.

Reference: [GitHub required status checks](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks).

## Evidence Boundary

- Keep the existing `status`/`passed` observation for merge-oriented consumers.
- Add `verification_passed` and `verification_issue` for an explicit-success view.
- At every acceptance boundary, recompute from retained check rows rather than
  trusting either boolean. Require immutable repository/commit binding, unique
  typed check identities, complete status/conclusion, zero pending/failing checks,
  and a matching content fingerprint.
- Both check runs (`completed` + `success`) and legacy commit statuses (`success`)
  retain their distinct observation types. A legacy status remains a provider's
  reported status, not a parsed test report.
- Empty, skipped, neutral, unknown, malformed or rebound observations cannot
  complete a campaign dependency or qualify retained-candidate integration.
- Old terminal watches without sufficient evidence reopen on startup. Historical
  observations are retained; a fresh rerun or verified descendant integration can
  unblock the task without recreating its implementation or publishing again.
- Before a dependent task dispatches, revalidate its publication against the
  current watch, including dependencies marked completed in old checkpoints. The
  pinned source must contain the currently verified integration commit.
- A pending dependency check defers child creation/start with a durable waiting
  checkpoint. After evidence recovery, the same reserved task identity proceeds;
  this does not spend a model attempt merely to discover stale evidence.
- Network failures keep the existing recoverable observation-error behavior.
  An unverified merged PR stays under the existing five-minute observer cadence;
  skipped checks do not themselves launch an implementation repair task.

This gate conservatively requires every reported check to explicitly succeed. It
does not infer that an optional skipped check is irrelevant. Task-bound required
check selection and verification-report coverage need a separate explicit contract.

## What This Does Not Prove

A successful CI check can run inadequate tests, a no-op workflow or an arbitrary
external integration. This change does **not** qualify CI as a general scientific
or computational validator, prove original-goal coverage, authorize external
experiments, or connect the Android team to a new execution sandbox. Meaningful
test reports, acceptance-to-test mapping, independent verification and equal-budget
team evaluation remain separate requirements of the full multi-agent goal.

## Verification

The test runner isolates HOME, APPDATA, Codex configuration, databases and task
workspaces before importing backend modules. It accepts explicit unittest module
names; with no arguments it preserves the existing collaboration evidence suite.

Regression coverage includes:

- merge-friendly versus explicit verification, mixed success/skipped results,
  legacy statuses, duplicate contexts, wrong commits, stale fingerprints and
  cached top-level pass flags;
- real temporary Git repositories with preserved candidate bytes, additions,
  deletions, mode changes, renamed paths and a 1,000-path candidate;
- database reopen, observer retries, actual subprocess-death recovery already in
  the CI/campaign suites, dependency waiting/recovery without repeated execution,
  and final campaign verification;
- unchanged merge controls and existing repair/start/publish authorization tests.

## Results: 2026-10-03

- Full Evolution v2 selection: **723 tests passed** in 720.076 seconds. This run
  preceded the final dispatch-preflight and repository-binding additions.
- Final frozen-source affected regression: **225 tests passed** in 99.825 seconds,
  including those additions, pause/resume during dependency waiting, source
  continuation checks, real Git integration and process recovery.
- Existing Desktop Node regression: **68 tests passed**; structure check passed.
- Changed-file 150 KiB policy and `git diff --check` passed. The repository-wide
  checks outside these suites were not rerun.
- The initial unittest discovery command could not import the namespace-style
  test directory. The full selection was then loaded by its 69 explicit module
  names through the same isolated runner; no tests were silently omitted.
- Latest main was refreshed before publication. Its intervening Android changes
  did not overlap this Desktop implementation; no Android production files are
  changed by this phase.
- GitHub responses in the regression are fixtures. Git commands, temporary
  repositories, SQLite journals and subprocess recovery are real local execution.
  No paid model calls, original research tasks, contact actions or physical tools
  were invoked by these tests. The running Desktop was not replaced or restarted;
  this phase has not yet been deployed for a live provider/campaign run.
