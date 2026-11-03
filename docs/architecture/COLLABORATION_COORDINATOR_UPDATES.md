# Coordinator Updates

An incremental coordinator can outlive its dispatch-time inventory. A producer may
publish a candidate or frozen validation data while the coordinator is still
working. The old immutable input snapshot remains valid but is no longer a full
description of what the team has published.

## Contract

`collaboration_recall` accepts `mode: "team_updates"` and an optional `cursor`.
The phone resolves the exact current run, turn, round, node and person from the
existing source binding and durable team checkpoint. Only an active incremental
coordinator can use this mode. Models cannot select or grant themselves a role,
group, producer, member or run. Pause, stop, completion and supersession deny new
updates.

The result contains published milestone descriptors with exact version references,
host tokens and `next_cursor`. Follow that cursor until `milestones` is empty,
then reuse the tail cursor when checking for later publications. An empty page
means no new versions at that read, not that a producer has finished.

The host journals each nonempty page and its exact read grants atomically. Repeating
an earlier cursor returns the same page, including after reopening storage. New
publications cannot silently replace a replayed page. Empty tail reads are not
permanently cached in the journal. The transport's existing per-request replay
mechanism still applies; a later poll is a new request with the saved tail cursor.

## Evidence And Isolation

The original dispatch inputs, source binding and goal/context snapshot never change.
An additional journal records versions **offered**, not necessarily delivered,
read, understood or verified. Only these exact workspace revisions and their
recorded evidence become readable through workspace/evidence recall. Later
revisions, unpublished drafts and unrelated current-round tool observations remain
isolated. Evidence page delivery confirmation remains separate from discovery.

Ordinary workers and independent reviewers receive no live-update authority.
The coordinator must still assign exact tokens to a new check or explicitly bind
an unadmitted review. Existing author-independence, prerequisite roles, admission
checks and version-bound review rules continue to apply.

At the planning checkpoint, offered descriptors are stored separately from the
original inputs so returned work and review bindings can reference them. This
does not mark the producer finished, complete the team goal, or replace a reviewer.
Offered pages alone do not suppress the normal next-checkpoint notification for
new milestones: an unconfirmed offer is not proof the coordinator considered it.

## Expected Benefit And Verification

This mechanism enables evidence-based coordination when results arrive during an
active planning step. It does not choose the scientific method, decide evidence
sufficiency, guarantee a useful review, or establish multi-agent superiority.
Those outcomes still require fresh, budget-controlled real-model trials.

Regression coverage includes late prerequisite publication, exact revision access,
immutable replay, tail polling, encrypted recovery, role and run isolation, pause
and resume, original goal binding, evidence read confirmation, independent worker
isolation, and binding a queued review without completing its producers. Pagination
is a delivery mechanism, not a total research-source limit.
