# Scheduled Final Verification Acceptance

## Scope

Desktop source 1.1.8, implementation `9bdc76f6e`, based on main `4039ecb39`.
This increment schedules the previously explicit original-goal review and adds
durable recovery and applied-retirement evidence. It does not enable production
self-evolution, change the original completed campaign, install an Android App,
or replace the running Desktop.

## Host Verification

- A complete development snapshot passed 669 evolution tests in 938.294 seconds.
- Two subsequently added boundary tests passed within a 53-test selection.
- The fixed submitted snapshot passed **671/671 evolution tests** in
  **1,358.306 seconds**. No implementation changes were made during that run.
- A separate 77-test selection covers the generic DAG, final-review parser,
  scheduler, evidence adapter, subprocess recovery and latest Codex startup
  contention regression. These counts overlap and are not additive.
- All 29 Desktop tests, Desktop structure, repository checks and whitespace
  checks passed. The inherited multitask-isolation report was translated without
  dropping its limitations so it passes the existing repository language guard.

Real subprocess termination uses `os._exit(83)` immediately before and after the
durable finish transaction. A new process opens the same state and retains one
inference, one task and one final proof. Controlled model and publication
observations in those tests establish host mechanics, not live model accuracy.

Applied-history tests use a real SQLite event ledger. They cover repeated failed
replacements, pruning pending work, replay after reopening the ledger, changed
projections, absent or modified recovery contexts, missing checkpoint proofs,
and matching the applied checkpoint command to its exact content-addressed proof.
Failed predecessors are never relabeled as satisfied tasks.

## Live Local Model Replay

The model is Qwen3-4B-Instruct-2507 Q8_0 using llama.cpp b10839 on CPU with six
threads, an 8,192-token context and a literal-loopback endpoint. No cloud model
is used. Timing here is desktop-local validation cost, not phone chat latency.

The source is the historical Chinese goal and publication evidence for
[PR #2892](https://github.com/galaxyssi/GalaxySSI/pull/2892), from proof
`5c870d78b9cd5bd7a7252000abd9ec9eb3f8d2b6835050013d25e741b4103a56`.
The harness checks the proof hash, reads immutable before/after files from Git,
and checks current PR head, merge identity, title and body against that evidence.
It does not reopen or complete the historical campaign.

| Control | Expected | Observed | Seconds |
| --- | --- | --- | --- |
| Complete original Chinese goal and actual result | pass | pass | 415.313 |
| Requested new content removed from the candidate evidence | fail | **pass: incorrect** | 330.187 |
| PR title/body changed to the wrong requested language | fail | **pass: incorrect** | 459.781 |
| Actual publication metadata absent | fail or inconclusive | **pass: incorrect** | 529.313 |

The content-negative deliberately retains the old publication description and
acceptance claims while changing the supplied candidate file contents. The model
accepted the claims instead of verifying the missing source content. This is a
failed independent-review control. It is not an observed production completion:
the replay bypasses the production collector to isolate the model; production
still independently binds candidate bytes and literal/preservation contracts.
Those host checks do not prove arbitrary semantic requirements are correct.

The language control retained correct English source content but replaced the PR
title and body with Chinese. The reviewer described the document correctly and
omitted the publication-language requirement. The missing-publication control
retained integration/acceptance claims but removed actual title/body evidence;
the reviewer inferred completion from those claims. Both are incorrect passes,
not correct rejection for an unrelated reason. The observed result is **1/4**
expected verdicts. No result grants new completion or publication authority.

Raw responses, evidence and durations are retained locally in
`build/final-review-live-evidence.json`. The harness is
`tools/testing/verify_final_review_replay.py`; it never edits GitHub metadata or
campaign state. The final GitHub read confirmed publication metadata remained
unchanged after all four controls. The temporary local model server was stopped.

## Release Boundary

The new scheduler mechanics are independently testable, but verifier qualification
has not passed. The earlier compound source-scope controls remain unresolved;
this positive replay does not erase them. A completely new autonomous candidate
publication, CI observation/repair and final completion without manual intervention
has not been demonstrated by this increment. PR #2902 was submitted as draft,
then made ready and merged externally while live validation was still running.
The findings were posted on that PR; this report is a separate follow-up and
does not alter the merged branch or treat merge status as acceptance.

All reported CI checks for implementation `9bdc76f6e` subsequently passed,
including the complete backend job, Android builds, repository checks, Desktop
smoke and Windows packaging. Those CI results do not include the opt-in local
semantic replays and cannot override their failures.

The [complete backend job](https://github.com/galaxyssi/GalaxySSI/actions/runs/34228987449/job/102070048929)
reported **2,592 passed, 12 skipped, two warnings** in 1,103.09 seconds for the
submitted implementation. The skipped tests are not claimed as exercised.
