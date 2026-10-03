# Live Candidate Repair Acceptance

`CollaborationLiveCandidateDeviceTest` is an opt-in product test, not a development
subagent. It uses the authorized phone's paired Codex and configured DeepSeek. It
creates three distinct digital-person identities: a Codex author/coordinator, a
DeepSeek editor, and a separate DeepSeek reviewer. Shared model weights do not make
the editor and reviewer statistically independent; their assignments and authorship
are isolated, and no multi-agent superiority claim follows from a passing run.

## Scenario

1. Codex performs one real read-only arithmetic command with a fresh fixture token.
2. Codex publishes two saved candidate documents. One deliberately contains a wrong
   sum/mean as a negative control; the other describes the real command output.
3. The real coordinator enrolls both exact versions in `candidate_cycles` while an
   unrelated, explicitly local harness gate remains active. No returned model JSON
   is repaired or replaced by the test.
4. DeepSeek independently reads the original evidence and candidate revisions.
   The incorrect candidate must receive a refutation and the correct one support.
5. A different digital person repairs only the refuted candidate, preserving its
   original version and the exact review basis. The original reviewer rechecks it.
6. The test checks three source-citing reviews, one repair, actual original-evidence
   fetches per review node, unchanged alternatives, durable graph-before-dispatch,
   and no repeated successful model work.
7. A final assessment keeps goal acceptance distinct from member candidate reviews.
   This scenario intentionally does not provide full semantic goal-coverage review
   and must not declare the original goal achieved.

The supplied arithmetic is not scientific validation or a real research benchmark.
Tool restrictions are in the task instructions, not a complete provider sandbox.
Recorded tool evidence cannot prove absence of unrecorded tools. No personal
conversations, contacts, doors, original research, or other devices are in scope.

## Running

Install matching application and instrumentation APKs and keep the authorized phone
unlocked. This test is not for unattended CI or unapproved providers/devices.

```powershell
adb -s AUTHORIZED_SERIAL shell am instrument -w -r `
  -e collaborationLiveCandidates true `
  -e class com.galaxyssi.chat.CollaborationLiveCandidateDeviceTest `
  com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner
```

The 15-minute harness deadline is not a product goal-step limit. A separate
90-second cleanup deadline persists STOP and reconciles managed remote ownership.
The dedicated group and database are removed only after local settlement and zero
pending remote owners; an unacknowledged stop retains fixture data for recovery.
The previously selected conversation is restored. Synthetic audit reports are
written to `live-candidates-UUID.json` in the app's external files directory.

## Source Citation Boundary

An evidence recall page exposes `source_reference` with the original ID, digest,
origin, tool and status. Its outer `galaxyssi_evidence_receipt` records the new read
operation. These are different observations. A reviewer satisfying a required
Desktop command source must cite the original `source_reference`, not substitute
the cloud recall receipt. The host still resolves every ID/digest and enforces the
original source contract; no reference is promoted into a verified claim.

The same original reference accompanies every page. Full reading, interpretation
and verification remain separate requirements. Invalid hashes and inaccessible
sources do not expose a reference. Ordinary workspace reads are not represented
as original execution evidence.

A candidate repair's negative-review reference belongs in `body.candidate.basis`.
It is not a `resolves` reference: that collection accepts preserved questions,
counterexamples, and supported candidate-challenge links, not review records.
Review-derived automatic repair instructions explicitly request `resolves=[]` and
the exact original candidate as the sole parent. Validation remains unchanged.

## Recorded Findings, 2026-10-03

- The existing live evidence-acceptance test failed on Android 1.4.22 after real
  Codex execution and DeepSeek source reading. DeepSeek cited its recall receipts
  instead of the required original Desktop observation. Host acceptance correctly
  rejected the completion claim. Explicit original `source_reference` metadata and
  citation guidance address that ambiguity without relaxing source requirements.
- First candidate attempt on 1.4.23: **failed in 245.428 seconds**. Both actual
  DeepSeek reviews cited the original Desktop observation and correctly refuted
  the negative control / supported the accurate candidate. Repair publication was
  rejected because the model put its review basis into `resolves`. The revised
  protocol wording separates these fields. This attempt is not a passing full
  candidate cycle. Durable STOP was acknowledged and fixture cleanup completed.
- Second candidate attempt on the final 1.4.23 APK: **failed in 219.596 seconds**.
  The author executed the real command and the coordinator enrolled candidate
  work, but a review reused a candidate object ID with a different kind. The
  workspace correctly rejected it with `An object's kind cannot be changed`.
  No complete repair cycle was verified. Durable STOP was acknowledged and the
  dedicated fixture was cleaned up. Prompt clarification alone is not sufficient
  for reliable structured publication; typed rejection feedback and safe repair
  inside the model/publication loop remain necessary.
- Four targeted device regressions passed on the final 1.4.23 APK in 2.650 seconds:
  scoped recall, encrypted cloud evidence, native tool evidence, and concurrent
  candidate progression. The separate-process seed/recover pair also passed
  (PIDs 24770 and 24878; 0.569 and 1.692 seconds). Already published revisions were
  preserved without duplication. These establish local recovery, not live-provider
  restart or Doze acceptance. These six invocations had no assumption skips.
- The existing full live-acceptance retest still failed: original Desktop evidence
  was cited correctly, but DeepSeek emitted `global_verdict` rather than the typed
  semantic review's required `verdict`. The workspace rejected publication, and
  Codex correctly requested follow-up work instead of claiming completion. This
  static three-node fixture does not execute that new work. Reliable typed-output
  repair within the model/publication loop remains open; this is not a passing
  end-to-end goal-acceptance sample.
- Debug application/test builds and **474 JVM tests in 35 suites** passed with no
  failures, errors or skips. The source-size gate and `git diff --check` passed.
  The repository-wide check remains blocked by existing i18n findings in unchanged
  files and local diagnostic artifacts, not by this change's files.

Remote Codex editing via on-demand phone workspace recall is not exercised here:
the editor uses the Android cloud adapter. Provider outages, real-process recovery
during a candidate cycle, long-duration memory and equal-budget quality comparisons
remain separate acceptance work.

## Related Coverage

- [Real-provider acceptance, 2026-10-03](COLLABORATION_REAL_MODEL_ACCEPTANCE_20261003.md):
  a new clean candidate challenge/repair/recheck pass on Android 1.4.32 and
  Desktop 1.4.5, followed by a separate multipart host-acceptance pass. Earlier
  failed samples above remain failures; the report documents exact scope and
  outstanding status, latency and resilience work.

- `CollaborationLiveEvidenceDeviceTest`: real provider evidence transfer plus host
  documentary acceptance and semantic coverage.
- `CollaborationCandidateRuntimeDeviceTest`: deterministic encrypted-device graph
  test and separate-process saved-publication recovery. These are local fixtures,
  not real provider interruption tests.
- `CollaborationScopedRecallDeviceTest`: exact source/read-receipt distinction,
  pagination, hash mismatch, independent-member isolation and revocation.
