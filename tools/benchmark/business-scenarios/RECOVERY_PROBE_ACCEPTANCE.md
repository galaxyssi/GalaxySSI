# Business Recovery Probe and A007 Delivery Failure

## Scope

The artifact campaign remains 100 cases and 1,100 turns. Its catalog SHA-256 is
`945c11225d2f7268e43403c09c7f0bc8158c579168b65e3c32a4b16ba9a113bc`.
This change repairs an opt-in diagnostic, not production delivery. No app or
Desktop version is changed. The installed Active3 app remains 1.3.26 (1069).

## Probe Defect

`recoverSyntheticCheckpoint` manually assembled a body-recovery identity but
omitted `agent_id`. The body-transfer entrypoint rejected it before publishing.
An `eligible=true` observation was insufficient to prove that a transfer began.
The old probe's 90-second empty result must not be cited as an archive-protocol
failure.

The diagnostic now uses `AndroidAgentRemoteRecovery.recoverPendingReplies`,
the normal application entrypoint. It retains normal Agent resolution,
authenticated status discovery, execution-generation checks, pacing and
terminal-state fences. It never resubmits a model or changes a task identity.

It also:

- Waits up to 30 seconds for request/reply readiness before probing.
- Records route-binding eligibility and the observed remote status/generation.
- Requires an artifact-bearing final reply for every pending turn; a streaming
  entry, approval request or delivery-error text is not success.
- Writes timestamped probe evidence instead of overwriting an earlier attempt.
- Rejects a checkpoint with no pending delivery; it does not resurrect it.

Finding a file/image block only checks reply recovery. It does not prove that
the binary arrived, has the expected hash/content, opens, saves, or renders.
The existing late-artifact and image-UI audits remain required.

## Preserved Real Failure

Device: Active3 SM-T575, Android app 1.3.26 (1069).
Run: `active3-warehouse-pptx-20260929-v1325`, case A007, turn index 7.
Task: `278ffe2e-071b-3851-bd62-a6ae45689df1`.
Phone turn: `7285c34d-d0ac-48cc-949d-625a49ad916c`.

The request adds an English summary and bilingual labels to the existing
Chinese PPTX while preserving its data. Desktop completed the model task in
243,647 ms and recorded five imported artifacts (one PPTX and four PNGs).
The phone observation timed out at 600,445 ms without a final reply.

The raw eight-observation A007 report SHA-256 is
`5f652c6850c7cd9716d445c2c918f1cf3c56909b2d1383b7bb9f03353c51a211`.
Its original `observation_timeout` was not rewritten. Turns 8-10 were not sent.

Subsequent read-only checks found a failed final-message outbox row with six
attempts, three queued chunk rows, and only two of five artifact ledger entries
marked stored. This is not evidence of a large receive backlog: at the sampled
instant Desktop ingress had zero pending/active jobs. Broker paths had changed
generation during the run; these observations do not identify a broker outage
or prove that every unsuccessful attempt reached the network.

The phone later settled the parent workspace as `FAILED` with the localized
message meaning "Desktop completed the task, but the reply was not delivered."
The subsequent probe rejected it as having no pending synthetic checkpoint.
This is a delivery failure, not a successful PPTX turn or recovery pass.

The running Desktop instance has not been replaced with the pending local
admission-accounting fix in PR #3296. Fresh-runtime delivery acceptance is still
required; no live outbox/database records were edited to force a result.

## Validation

- Android instrumentation APK assembled successfully (final incremental build:
  1m 9s); only the test APK was replaced for this diagnostic change.
- 32 host catalog/report/content-review/timing tests passed.
- Active3 read-only checkpoint inspection passed and confirmed `FAILED`.
- The final diagnostic build rejected the settled checkpoint before recovery.
  A successful new real recovery transfer is **not yet verified**.
- An intermediate probe recorded `publish_rejected` before transport readiness
  and a text-only delivery error. It is preserved as failed evidence; the final
  probe adds readiness waiting and does not accept that text as artifact success.

No credentials, private conversations or binary test artifacts are included in
this document. Raw device evidence remains outside Git.
