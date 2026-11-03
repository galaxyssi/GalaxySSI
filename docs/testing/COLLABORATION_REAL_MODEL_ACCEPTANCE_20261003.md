# Real-Provider Collaboration Acceptance: 2026-10-03

## Result and Scope

Two fresh, explicitly authorized real-provider instrumentation tests passed on
S26U. They used paired Desktop Codex and the phone's configured DeepSeek through
the production member worker, encrypted transport, workspace publication and
host acceptance paths. The tasks were dedicated synthetic documentary fixtures;
the user's original research, contacts, door actions and other devices were not
run or changed.

| Acceptance slice | Result | Instrumentation duration |
| --- | --- | ---: |
| Two candidates, independent challenge, correction and independent recheck | `OK (1 test)` | 467.757 s |
| Original evidence transfer, multipart goal coverage and host-confirmed delivery | `OK (1 test)` | 442.965 s |

These are two successful samples, not a measured production success rate or p95.
They close the previously unverified real-provider candidate correction cycle
and confirm the evidence-delivery path on the current Android build. They do not
establish general scientific correctness, autonomous planning quality or a
quality/cost advantage over a single Agent.

Environment: Android **1.4.32 (1117)**, Desktop **1.4.5**, source checkout
`b7a346d7c` (the Desktop CI-verification change in PR #3356; Android collaboration
code is unchanged from merged PR #3355). The matching app and instrumentation
APKs were already installed. This report makes no production or test changes
and does not publish another application version.

Desktop was initially stopped. The first startup selected an older Python
runtime without `httpx`, so MQTT did not start. That idle instance was replaced
using the existing complete Python runtime and the freshly built current Signal
sidecar. Testing began only after `/health` reported ready, connected and all
19 expected subscriptions active. Existing pairing and user data were retained.

## Candidate Challenge and Repair

Run: `live-candidates-794ac717-5fce-4103-914b-613c35accd2b`.

The three digital people used Codex as author/coordinator, DeepSeek as reviewer,
and a separate DeepSeek member as editor. Separate member identities provide
authorization and authorship separation, not statistical independence between
copies of the same underlying model.

The unchanged `CollaborationLiveCandidateDeviceTest` verified:

- A real read-only Codex command returned the unique fixture token, `15` and
  `3.75` for the sum and mean of `1,2,4,8`.
- Two distinct candidate originals were saved: an explicitly unverified negative
  control (`sum=16`, `mean=4`) and the accurate alternative.
- The independent reviewer cited and fetched the original Desktop observation,
  refuted the negative control and supported the accurate alternative.
- The editor saved revision 2 with `sum=15` and `mean=3.75`, preserving its
  previous-version hash. The reviewer independently rechecked and supported it.
- All three reviews cited the actual Desktop source and fetched that source in
  their own dispatches. The original negative-control revision was unchanged;
  the correct alternative did not acquire a replacement revision.
- Candidate work proceeded while an unrelated local synchronization gate was
  still waiting. That gate was neither a model nor accepted evidence.
- Each recorded worker assignment was invoked once. All four candidate
  publications were recorded on publication sequence 1. This sample therefore
  does not exercise rejected-publication repair or reviewer reassignment.

The coordinator correctly retained `decision=continue` and the original open
criterion: candidate events are not a substitute for host goal acceptance and
semantic goal coverage. This fixture deliberately does not authorize that next
stage. The second, separate fixture below tests qualified final acceptance.

The audit reports `candidate_cycle_verified=true`, one original Desktop
observation, `stop_acknowledged=true` and `retained_for_recovery=false`.
Its final stored state is `INTERRUPTED` because cleanup explicitly applies
durable STOP to the continuing goal after all assertions pass. This is not a
failed candidate cycle or a claim that the original goal was achieved. Only the
dedicated group/database were removed, and the previously selected conversation
was restored.

## Evidence and Final Delivery

Run: `live-evidence-fe7616c9-3131-44b0-8e32-1a7b121df710`.

The unchanged multipart, headless
`CollaborationLiveEvidenceDeviceTest#remoteAuthorIndependentReviewerAndHostAcceptance`
used four real assignments: Codex author, DeepSeek reviewer, Codex coverage
directory author and Codex final assessment. No Activity was launched and the
user's selected conversation remained unchanged.

All four assignments were `SUCCEEDED`; final state was `SUCCEEDED`, disposition
was `achieved`, and the production host accepted the documentary criterion and
multipart semantic coverage. The fixture checked exact saved document versions,
two separately authored mappings, independent mapping reviews and their saved
coverage directory. No expected output was substituted for a provider response.

DeepSeek's review and Codex's later directory publication both froze complete
`scoped_pages` coverage of the same original command observation: **3,301 of
3,301 characters**, matching evidence, source and content hashes, under their
own six-field reader identities. This proves recorded original delivery; full
byte coverage by itself does not prove comprehension or general claim truth.

The run-bound cleanup receipt acknowledged durable `STOP`, had no pending remote
owners and set `retained_for_recovery=false`. After both tests, read-only Desktop
task-store inspection found no queued/starting/running/recovering records, and
the Desktop Agent Runtime reported zero active, queued and pending futures.

## Observed Timing and Residual Issues

These elapsed times come from stored Desktop task timestamps and phone workspace
publication receipts, not from progress-text timing. They include real provider
work and transport; the final row has no separate publication measurement.

| Assignment in the second run | Desktop started-to-completed | Completion-to-phone publication |
| --- | ---: | ---: |
| Author | 95.412 s | 14.799 s |
| Coverage directory | 170.984 s | 6.563 s |
| Final assessment | 73.671 s | Not separately measured |

The total 442.965-second test also includes setup, DeepSeek review, scheduling,
validation and cleanup. It is not a normal-chat response-time target.

Residual observations are not hidden by the passing assertions:

- Original recall encountered transient confirmation timeout / publication
  failures. Later scoped reads succeeded and the required coverage was present
  before acceptance. The bridge's `Originating phone is offline` message is
  triggered by a failed publish, so it alone cannot prove that the phone was
  actually offline. This was not a controlled long-outage test.
- Desktop logged an existing reputation-ledger `head_signature_invalid` warning
  and deferred that separate reputation receipt. This run did not reset or
  bypass that ledger; reputation-based team adaptation remains outside this
  acceptance result.
- `/api/agents` still exposed a historical Codex `busy` / `active_tasks=1`
  snapshot with an old `runtime_updated_at`, despite the empty durable task
  store and runtime scheduler after cleanup. This stale availability projection
  is a separate unresolved status issue, not an unfinished fixture task.
- Additional latency optimization and repeated samples are needed. Controlled
  Doze, long network loss, process death during this exact candidate cycle,
  reboot, months-long memory, qualified scientific/computational validation and
  equal-budget single-Agent comparison remain separate acceptance work.

## Reproduction and Evidence

Use the test fixture's existing authorization gates; do not run against original
user research or substitute a different connected device. `<S26U_SERIAL>` must
identify the explicitly authorized phone.

```powershell
adb -s <S26U_SERIAL> shell am instrument -w -r `
  -e collaborationLiveCandidates true `
  -e class com.galaxyssi.chat.CollaborationLiveCandidateDeviceTest `
  com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner

adb -s <S26U_SERIAL> shell am instrument -w -r `
  -e collaborationLiveEvidence true `
  -e collaborationLiveHeadless true `
  -e collaborationLiveMultipart true `
  -e class com.galaxyssi.chat.CollaborationLiveEvidenceDeviceTest#remoteAuthorIndependentReviewerAndHostAcceptance `
  com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner
```

The 15-minute and 12-minute deadlines are bounded test harnesses, not production
goal-step limits. Both have a separate 90-second STOP reconciliation guard and
retain fixture state if remote ownership cannot be safely settled. Safe test
instructions are prompt-level restrictions, not an operating-system sandbox.

Run-bound synthetic reports were retained locally only. No raw conversations,
credentials, pairing material or report payloads are committed. SHA-256 digests
allow the retained reports to be matched without publishing their contents:

| Local report | SHA-256 |
| --- | --- |
| Candidate audit for `794ac717-5fce-4103-914b-613c35accd2b` | `78b3c9bb7440650ae2ef236bdf1e1df5ba868d5383ff8e468ac4b2f97e898cb9` |
| Evidence run mode | `a476104c5f1b65e5c502911d5dcf6eaf195613bb3586aa69e0351e16bd680fe8` |
| Evidence snapshot | `abd6099bb5c8d74413e768cec1b45d81d4d20bc4acc14aa6ca74f262aa7f06ed` |
| Evidence read coverage | `4aee61b0482c3ec6174dc78652e0a5b4d02b03a176477dbdc8e795ed1f263748` |
| Evidence cleanup for `fe7616c9-3131-44b0-8e32-1a7b121df710` | `d89f43d4b0fecb3848d323273fb48e5e956e5f6bb6ae719ae948a8f8018b1d1c` |

See also [candidate-cycle protocol](COLLABORATION_LIVE_CANDIDATES.md) and
[background evidence delivery history](COLLABORATION_BACKGROUND_LIVE_ACCEPTANCE.md).
