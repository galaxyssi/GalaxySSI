# Evolution publication reconciliation

Desktop 1.0.42 records a publication intent after candidate validation and before
any push or PR creation. The intent binds the repository, base branch, candidate
branch, and reviewed commit. It survives manager and process recreation.

## Side-effect handling

The publisher queries GitHub for all PRs associated with the exact head/base
selection, then reads the individual PR to verify repository and commit identity.
An already-published candidate is reused without another push or create. An
ambiguous result, changed head, foreign repository, or closed-unmerged PR does
not authorize replacement publication.

When no PR exists, Git pushes the reviewed SHA explicitly, not an unpinned local
branch tip. The publisher checks again before creation and after the command
returns. A timeout or failed command response can still have produced a PR; a
verified remote result wins over that uncertain local command outcome. Conversely,
a successful command exit or a printed URL alone cannot mark publication complete.

## Restart recovery

While holding OS task ownership, recovery reconciles an interrupted `publishing`
record against its saved intent. A matching PR restores `published`, its URL, and
the CI observation watch. A watch-index write failure leaves publication intact
and requests the existing CI index repair path.

Unknown GitHub observations retain `publishing` and a specific error. Enabled
recovery scheduler ticks retry that observation. Disabled self-evolution does not
poll or automatically publish. Records predating saved intents retain their prior
explicit reconciliation state. CI repair publication continues to target its
original PR and checks the repaired candidate SHA rather than creating a new PR.

## Validation scope

Tests cover successful publication, existing PRs, lost and failed create responses,
unconfirmed success, head/base/repository changes, closed or merged PRs, duplicate
and malformed pagination, durable intent mismatch, offline recovery, manager
recreation, CI-watch write failure, and a real local Git push of a reviewed commit
when the checked-out branch has already advanced.

Read-only GitHub acceptance verified the actual head of PR #2860 through the same
matching function. This does not prove that every external command has exactly-once
semantics. Orphan coding CLI processes, arbitrary external tool side effects,
multi-day continuation, and device reboot acceptance remain separate work.

`tools/testing/run_evolution_publication_acceptance.py` can publish an already
reviewed feature branch with explicit `--allow-publish`. It injects a local timeout
after a successful real `gh pr create`, reconciles the remote identity, invokes
publication again, and records whether the same PR was reused in isolated state.
It requires a clean source checkout and an explicit origin repository and branch.
This harness exercises only the post-validation publisher, not immutable gates or
the implementation Agent. Do not run it on an unreviewed candidate.
