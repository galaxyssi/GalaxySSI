# Android #3119: Journal-backed Codex Recovery Dispatch

Baseline: main `26e82a54754c11aab4e32c09fc1c389ff1b13628`.
This is an independent iOS follow-up, not completion of #3119 or the backlog.

## Missing Production Path

The existing authenticated terminal-reply path can schedule an explicitly bounded
Codex recovery attempt with a distinct UUID source. But `publishLinkMessage`
rejected all replay records on journal transport, and the pending-dispatch sweep
required the legacy MQTT client's subscription readiness. The journal connector
projection also only recognized visible message UUIDs and team-owned UUIDs.

The sweep can now enqueue pending replay attempts into an available journal
runtime; it need not wait for a legacy connection. Actual network dispatch remains
under the journal runtime's original readiness/route/session/send-owner checks.
Legacy readiness behavior is unchanged. The shared publisher's existing replay
scope, invocation, disclosure and task-budget checks still precede enqueue.

## Current Replay Ownership

A new optional connector projection callback maps an attempt UUID to exactly one
current encrypted recovery record and its original saved outgoing message. It
requires the current profile/protected data, connector enablement, a verified
same-Desktop endpoint/route/registered task identity, automatic selection, an
active nonprivate/nonpaused/nonmerged non-team session, a current original source,
the existing unexhausted budget's exact expected target and still-supported
original model/effort. Terminal, accepted, manual, cancelled, managed-child and
team records cannot authorize this generic replay.

Outgoing replay payload validation binds the actual attempt message/source IDs,
public and internal task/conversation/turn fields, endpoint/agent/Desktop/route,
original prose and saved transport context. It requires plan-only execution,
disabled long-term writes, no attachments, voice, peer or team routing. The
origin's exact saved invocation is retained; alternatives do not inherit it.
No new wire field, numeric-to-UUID conversion or display-label inference is used.

The runtime's existing per-send owner hook rechecks the live callback, so queued
attempts lose permission when the record/source/session/selection is no longer
current. No new retry budget is created or spent by projection. The original
confirmed-timeout qualification, bounded attempt algorithm, superseded-binding
ledger, encrypted record schema and durable Signal wire/outbox implementation
remain unchanged. Silence alone still does not schedule a replay.

## Receipt Projection

An attempt UUID is not a chat-row UUID. For a matching current replay delivery
event, map only the local presentation write back to the original message UUID.
Keep the real attempt message ID, identity, wire hash, request hash and timestamp
for trace deduplication. Do not rewrite the immutable completion journal or wire
identity. Existing chat transaction and commit-before-consume behavior remain.
Progress already uses the connector task-owner lookup and now resolves the same
original message. Terminal result recovery keeps its existing binding path.

## Verification Limits

Seven authored-only Swift fixtures cover exact source fallback, identity/prose
mutations, privilege restrictions, manual/terminal records, origin/alternative
invocation, receipt mapping and actual connector request/send-owner/completion
projection. They are NOT compiled or executed. The dedicated source guard
compares the changed production files against the pinned baseline after only
declared hooks, freezing the recovery state machine, timeout resolver, transport,
journal, outbox, completion schema, chat database, disclosure and budget kernels.

This does not prove native queue/reconnect/receipt/restart, storage-fault, privacy,
UI or device behavior. No build/typecheck/XCTest run, CI monitoring or IPA. Recovery
records and outbox remain separate commits under existing unknown-publication
handling; no exactly-once external-effect or cross-store atomicity claim is made.
Cross-Desktop/cloud recovery, generic active timeout scheduling and full Android
parity remain separate work.

Source verification: nine guards passed (journal replay, raw attachments,
document input, owned status, pre-shadow, usage, health, provider ranking and
observation timing), plus `npm run check:ios`, changed iOS Han placement,
inventory JSON and diff whitespace checks. Historical manual-recovery and
stable-auto-admission guards both stop at their old model-selection-file baseline;
that failing file is identical to current main and is not edited here. These
results must not be reported as an all-repository or Swift compiler pass.
