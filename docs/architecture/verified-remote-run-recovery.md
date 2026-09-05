# Verified remote Run recovery

Android and Desktop use a read-only recovery query over their existing paired,
Signal-encrypted reliable transport. A locally saved handoff is a lookup hint,
not evidence that an Agent is still running. This applies to registered Desktop
Agents, not only Codex. iOS is unchanged.

## Scope and ownership

- Each request has a fresh random nonce, an authenticated Desktop destination,
  the currently paired route, and at most 32 identities. Larger sets are batched.
- Each identity includes route, conversation, task, turn, contact, source message,
  and Agent. Desktop checks all fields against its saved task before disclosure.
- The phone accepts only a response from the expected authenticated Desktop with
  the outstanding nonce, route, and exact identity set. Duplicates, mismatched
  scopes, missing items and late responses cannot complete another query.
- Status metadata never goes to chat listeners or system notifications. No prompt,
  answer, tool arguments or attachment content is included. Local-only global
  cognition and evolution conversations are excluded before publishing.
- The phone-owned Run device ID and remote executor device ID are distinct.
  Recovery verifies the latter against the selected Agent registration, while
  workspace ownership uses the local conversation, task and Run binding.

## Recovery semantics

The eight-second query timeout bounds one observation, not task execution. Failure
to observe a task leaves it waiting; it does not replay a command or start a task.
Queued/running, user-wait, paused, failed and cancelled states are not conflated.
A completed remote status is not a delivered answer: the local workspace remains
waiting for the existing result-delivery path to provide the actual response.

Recovery events use fresh idempotency keys. The encrypted Run ledger compares
the expected sequence and nonterminal state inside its write transaction before
appending. A local cancellation, newer progress or final result wins over a late
observation. Terminal workspaces are never reactivated by reconciliation.
Desktop status revisions are not event cursors and never advance the phone's
last consumed remote event cursor. Empty observations do not erase checkpoints.

## Verification

Unit suites cover authenticated scope, malformed batches, status mapping, stale
responses, cancellation, timeout, privacy exclusions and independent phone/remote
device IDs. Device tests use a separate encrypted database, reopen it, and check
that stale recovery cannot overwrite terminal state or newer tool progress.

An opt-in `AgentRemoteRecoveryDeviceTest` with `live_recovery_probe=true` queries
an existing paired task on S20U without creating, modifying, cancelling or
resubmitting it. It requires the new Desktop build to be running. Results and
deployment limitations are recorded in the PR; do not equate unit coverage with
a completed live paired-device acceptance test.

## Remaining boundaries

This phase reconciles authoritative status. Automatic final-result redelivery,
remote event-page replay, UI reattachment across every execution path, and the
five-second end-to-end recovery SLO still require separate acceptance work.
Run ledger and workspace projections are not one atomic transaction; guarded
projection writes prevent terminal rollback, but do not claim distributed
exactly-once effects or a fully atomic cross-store recovery operation.
