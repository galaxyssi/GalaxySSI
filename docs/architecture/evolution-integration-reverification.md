# Post-Merge Integration Reverification

Desktop 1.1.5 adds a host-owned evidence path for a published candidate whose PR
was merged with failed CI. Merging never changes that historical failure into a
success. A later, independently verified integration can instead satisfy the
campaign dependency.

## Evidence Required

The observer verifies all of the following:

1. The PR is merged into `main` in the same repository, with exact repository,
   PR, candidate SHA and merge SHA identities.
2. The saved accepted candidate and its original source commit are available.
   A changed PR head is not silently substituted for that accepted candidate.
3. GitHub's current `refs/heads/main` names an immutable commit. Fetching its
   objects does not change the user's checkout, index or uncommitted files.
   Shared `FETCH_HEAD` is not used as authoritative branch identity.
4. The observed main commit descends from the candidate's merge commit.
5. Every candidate-changed path has exactly the same Git tree state as in the
   accepted candidate. Added/deleted files, file modes and both sides of renames
   are covered. External diff, text conversion and submodule suppression are
   disabled. Two tree diffs avoid one subprocess per file. Unrepresentable or
   incomplete path evidence is rejected, not treated as empty.
6. All reported checks and statuses for the immutable integration commit are
   known and passing. Missing, partial, unknown, pending or failed evidence does
   not establish success.
7. The main ref and PR identities are checked again after verification. A race
   invalidates the observation and is retried using a fresh snapshot.

Changed candidate paths require fresh semantic acceptance; this path does not
infer that a similar-looking replacement is equivalent. Nor does it authorize
editing files outside the original scope to repair inherited CI failures.

## Durable Recovery

The CI watch stores `integration` separately from its original `snapshot`.
Both the historical failure and the new head-bound CI/fingerprint evidence remain
available. Merged failures without accepted integration are revisited every five
minutes while the scheduler is enabled. Previously terminal failed watches are
reopened during indexing. Verified integrations can stop polling; this records
an immutable historical integration, not a promise about all future main changes.

An active failed DAG node tied to that published task can then retry observation,
claim and complete through existing Run-ledger events. It never restarts the
published implementation or pushes the PR again. Intermediate process death
recovers the same task identity. Paused, cancelled and superseded work is not
automatically resumed. Dependency source checks use the newly verified integration
commit, so downstream work cannot build on an older base lacking the repair.

Normal unmerged PR repair, local inference, Android and iOS are unchanged. The
production self-evolution scheduler remains disabled by default. These are
dependency-integration checks, not full original-goal acceptance, configured
required-check enforcement, semantic revalidation of modified candidate files,
or acceptance of every device and provider path.
