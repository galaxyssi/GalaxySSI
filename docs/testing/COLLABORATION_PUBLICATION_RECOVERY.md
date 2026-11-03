# Durable Publication Correction

## Boundary

This phase adds host-validated publication feedback to managed Android cloud
research members. It does not change the original task, agent identity, access
scope, candidate requirements or goal acceptance rules. Desktop Codex publication
feedback needs a separate execution adapter; merely changing its prompt is not
equivalent to this loop.

The host enrolls the exact group/run/turn/node/person, dependencies, research stage
and optional candidate task before dispatch. Ordinary chats, goal controllers and
incremental planners keep their existing response protocols.

## State and Execution

1. Buffer the model's draft; do not show it as completed output.
2. Validate the complete workspace transaction with the existing validators.
3. On rejection, atomically save the draft and exact host error in an encrypted
   append-only attempt journal. No candidate or review is partially published.
4. Return the error and required schema to the same model conversation. Permit
   only scoped reads of already recorded collaboration evidence and workspace
   originals. Reject an entire forbidden tool batch before cache lookup or actual
   dispatch; a tool not advertised in the request is not implicitly authorized.
5. Publish the corrected complete response with the same authorship. Commit its
   revisions, publication receipt and attempt record together, then deliver it.
6. Reopening the assignment restores a rejected draft for correction, or replays
   a recorded response without another model call. A recorded publication cannot
   be replaced by a different result in the same dispatch.

Each attempt is digest-protected and chained to its predecessor. The transient
model context keeps only the latest correction draft/error pair; previous full
drafts remain in the journal. The pair uses stable conversation slots so evidence
projection callbacks cannot overwrite later tool observations after another repair.
Evidence-bearing rounds retain the existing citation and research-quality checks
before publication. Pause/cancel uses the existing coroutine and dispatch
ownership controls. Model timeouts remain retryable failures with the draft saved,
not a synthetic successful answer. Correction has exponential backoff, capped at
60 seconds between attempts, not a fixed attempt-count termination rule.

Storage failures, digest-integrity failures and revoked access are not model
formatting errors. They propagate without committing a new attempt or asking the
model to repair corrupted host state.

Successful publication proves schema, authorship, version and reference checks.
It does not prove that a scientific claim is true. Host goal acceptance and actual
independent verification still run separately. A successful publication must not
be advertised as experimental validation.

## Verification

- `CollaborationPublicationRecoveryTest`: malformed responses, verdict fields,
  kind changes, atomic rejected batches, write failure, identity isolation,
  revocation, digest corruption, immutable success, retry/backoff and cloud tool
  schemas.
- `CollaborationPublicationRecoveryDeviceTest`: actual stream engine against a
  loopback HTTP server, encrypted rejection/recovery, no premature output, no
  repeat call after publication, cancellation, and a forbidden-tool request. An
  evidence-bearing case also reads again during repair and checks that tool-call
  IDs still pair exactly with their results after the next correction.
- The same device class supports `publicationPhase=seed` and `recover` in separate
  instrumentation processes. Use the exact method selector so unrelated process
  fixtures are not counted as assumption-skipped passes.
- `CollaborationLiveCandidateDeviceTest`: real Codex producer/coordinator and
  DeepSeek editor/reviewer. This is separate from deterministic HTTP fixtures.

## Remaining Acceptance

Real-provider results for this revision must be recorded after testing; none are
implied by the design. Remote Codex correction, live-provider process death during
correction, Doze/long network outages, repeated-correction resource escalation and
equal-budget team quality comparisons remain separate work. A loopback test is
not evidence of provider quality or a scientific experiment.

## Results on 2026-10-03

- Android **1.4.24 (1109)** built and installed on the authorized S26U without an
  uninstall. No Desktop restart, personal conversation, contact or door operation
  was required.
- **482 JVM tests in 36 collaboration suites passed**, with zero failures, errors
  or skips. This includes eight new publication recovery tests.
- **Nine device tests passed in 76.995 seconds**: four publication stream tests,
  four existing managed stream framing tests and the detached cloud-stop test.
  The forbidden `web_fetch` request was rejected before execution; the loopback
  server received only the three model requests, and no tool evidence was created.
- Separate-process seed and recover both passed (PIDs **14286 / 14368**, **0.074 /
  1.292 seconds**). Recovery issued one corrected model request; replay after the
  successful publication made no further model request. These are deterministic
  loopback model responses, not real-provider interruption results.
- Kotlin source-size policy and whitespace checks passed. The repository-wide
  check still fails its pre-existing i18n findings in unchanged files and old
  local diagnostic artifacts.
- The real-provider candidate retest is recorded separately below. Previous failed
  live-provider samples remain in `COLLABORATION_LIVE_CANDIDATES.md`; they are not
  retroactively counted as passes.

### Real-Provider Retest

Run `live-candidates-d2afc8bc-a27f-42f9-8978-cb4c908f3c53` on S26U used the existing
Desktop instance and real Codex/DeepSeek calls. The test **failed in 904.772
seconds** at its 900-second harness deadline, not a product research-step limit.

- The actual Desktop arithmetic observation returned sum=15 and mean=3.75.
- Independent cloud reviews refuted the deliberate 16/4 negative control and
  supported the accurate alternative, citing the original Desktop observation.
- The editor published revision 2 with 15/3.75, preserving revision 1 and the
  separate correct candidate. Independent recheck supported the correction.
- All four cloud publications were recorded on attempt 1. This sample verifies
  those real member contributions, but does **not** demonstrate a live provider
  exercising the new rejected-format correction loop; that has deterministic
  device coverage above.
- The last incremental Codex planner completed at 03:05:40 local time and returned
  an empty additional-work list. The phone still showed that planner running and
  final delivery queued. The remote-evidence worker repeatedly returned RETRY;
  phone MQTT route maintenance also reported backpressure reason 32202. These
  observations localize investigation to completion/evidence synchronization but
  do not alone prove a broker failure or exact root cause.
- One manual result-only republish was issued through the local Desktop API for
  task `f1517e01-e69e-30ad-9330-483b355f867b`; it did not unblock the test and did
  not rerun the model. It must not be counted as automatic recovery.
- At the end of the test the phone was in WeChat, not locked. No WeChat contents
  were inspected or operated. Background completion remains required behavior,
  not a reason to waive this failure.
- Durable STOP was acknowledged, `retained_for_recovery=false`, and dedicated
  fixture cleanup completed. No original research, contacts, doors or other
  devices were operated. Full goal acceptance was not reached, and scientific
  validity or multi-agent superiority was not measured.

The next acceptance priority is the remote-evidence/completion wait. Do not rerun
the original user research to diagnose it, bypass evidence checks, or treat these
four saved contributions as a passing full end-to-end result.

Follow-up: the receive-capacity root cause, migration and subsequent passing
real-provider retest are recorded in [Evidence Inbox Recovery](COLLABORATION_EVIDENCE_INBOX_RECOVERY.md).
