# Campaign completion verification

## Scope

This run verifies the retained long Chinese document-development goal using a
loopback Qwen3-4B-Instruct-2507 Q8_0 model and actual Git/GitHub evidence. It is
not an Android performance run, production deployment, or completion of the
entire autonomous evolution and CI-repair roadmap.

The original goal requests an English Operational Recovery section appended to
`docs/architecture/source-preservation-contract.md`, preserving existing text
and changing no other file, followed by independent verification and an English
self-evolution PR. Candidate implementation was not manually rewritten.

## Original goal result

- Fresh original-goal review: **pass**, no unresolved findings, 359.0 seconds.
- Candidate: `013a98b5a5d2ff2aeb26bea465ee5cc283f4f6d0`.
- Source: `b9edb79574d80c55c601696901073fd99777a905`.
- Actual change: one file, five added lines, zero deleted lines; original text
  remains an unchanged prefix. The new section describes preserved constraints,
  restored source identity validation, rerun acceptance, and the inability of
  previous results to substitute current validation.
- Actual publication: [PR #2892](https://github.com/galaxyssi/GalaxySSI/pull/2892),
  created by the production publisher and subsequently merged. Its actual title,
  body, file list, head and merge identity were read from GitHub.
- Fresh integration verification: passed against
  `fb7f5b0e80dbbbfc87376148e745a94d74a0c0d7`, retaining the candidate bytes and
  all five reported main-commit checks passing. Historical failed PR-head CI is
  retained separately; it was not rewritten as a historical pass.
- Final evidence was collected again after inference before coordinator finish.
- Campaign `campaign-goal-d3239cfaeafc0a91863cc804aec3cd10` is `completed`.
- The acceptance manifest now reports `full_campaign_complete=true`, with zero
  active workers. This flag applies only to this particular acceptance campaign.
- Final content-addressed proof:
  `5c870d78b9cd5bd7a7252000abd9ec9eb3f8d2b6835050013d25e741b4103a56`.

## Restart verification

A fresh manager and planner process loaded the same isolated state. Three
planner/scheduler observation cycles left the graph unchanged and completed.
No model call, implementation start, active worker, or interrupted task recovery
occurred. One completed implementation node and one retired duplicate node remain.

## Failures retained during verification

The initial planner returned `proceed` even though its explanation said that the
next task was already satisfied. A clearer action description alone did not fix
this. Typed per-ready-node assessments removed that action-word ambiguity.

An initial independent retirement review was too lenient: it treated an opaque
task ID in the commit message as satisfying a generated requirement for a clear
description of the section. That is not reliable evidence. The review now demands
the specified field itself, not a different field or indirect implication. The
original user did not request that extra generated commit-message requirement;
the final original-goal review is distinct from this flawed child-criterion proof.
Excess generated requirements still require goal-level replanning, not a false
claim that they were satisfied.

The first final-goal model response put positive explanations in `findings`.
The existing validator correctly returned inconclusive. The harness now requests
only per-requirement verdict/evidence rows and derives aggregate status using
the existing validator. A fresh complete review was run; the previous response
was not edited into a pass. Negative verdicts, missing evidence, unknown fields
and duplicate JSON keys remain rejected or non-passing.

One supplemental negative-review attempt returned malformed JSON and did not
count as a semantic pass. Checkpoint inference now uses the local endpoint's
response schema as well as strict host validation.

**Historical failure: automatic retirement semantic counterexample.** A subsequent
schema-constrained real-model review returned well-formed JSON but still passed
the commit-message requirement using contextual implications from other PR
fields. Its duration was 323.672 seconds. The negative harness explicitly checked
for a `fail` verdict on that criterion and exited with failure. This is not a
passing negative test. Raw response and actual publication evidence are retained
in `build/checkpoint-negative-evidence.json`.

That failure kept the checkpoint-retirement increment in draft. A follow-up now
adds metadata-only evidence scoping, isolated field reviews, exact source quotes,
persisted failures and strict duplicate-key rejection. Its initial live matrix
rejected the original commit counterexample but exposed two further errors:
the wrong branch was called inconclusive, and the file-only criterion selected
PR prose rather than the changed-file list. These attempts remain in
`build/scoped-live-evidence.json`; four of six cases passed, not six of six.

Host field meanings were then added to distinguish actual file/branch facts
from PR prose. The full described-field rerun and multilingual/compound controls
are recorded separately, never by rewriting the failed responses. The successful
original-goal review is not proof that arbitrary generated child criteria are
evaluated reliably.

## Follow-up live verification

All inputs below came from the retained campaign and fresh GitHub publication
metadata for PR #2892, using the same loopback Qwen3-4B model. No candidate file,
commit message, PR title, or acceptance criterion was edited to force a pass.

- Field descriptions rerun: **7/8 controls passed**. English commit, branch,
  file-only and missing-review controls behaved correctly. A Chinese request
  about the commit description was incorrectly scoped to the PR body.
- Canonical Chinese field labels corrected that same Chinese counterexample;
  the original sentence and expected field were not changed. The Chinese
  English-language positive and a compound repository/branch positive also
  passed. A compound publication counterexample still returned an incorrect
  semantic pass, rejected only because its quotes were not exact decoded text.
  This batch was **3/4 passed**, not complete success.
- Source-quoted and subsequently indexed compound-guard experiments also failed
  real controls. The final indexed run used explicit temperature zero.
- Compound publication control, 250.688 seconds: the overall verdict was `fail`,
  but it rejected the title's language rather than the required commit-message
  description. This is **not** a successful regression result.
- Alternative destination control, 176.406 seconds: `develop OR the actual
  repository` should pass because the repository matches. The compiler and its
  independent reviewer incorrectly required each alternative separately, and
  the branch mismatch caused a false rejection. This control **failed**.

The harness now checks the causal field of the compound rejection, not only
its overall verdict. A read-only adjudication of the retained indexed responses
therefore records **0/2 passed**. It does not invoke the model again, alter any
raw response, or overwrite the original report; it binds the original report
hash and verifies publication metadata is unchanged. The earlier superficial
`passed=true` is retained as `previous_passed`, not concealed.

Artifacts retained locally:

- `build/scoped-live-evidence.json`
- `build/scoped-live-described-evidence.json`
- `build/scoped-multilingual-evidence.json`
- `build/scoped-obligations-evidence.json`
- `build/scoped-typed-obligations-evidence.json`
- `build/scoped-indexed-obligations-evidence.json`
- `build/scoped-indexed-adjudication.json`

**Verification executed, readiness failed.** PR #2899 is not deployment-ready,
regardless of its GitHub draft/ready-for-review presentation. The
remaining defect is not a missing test run: compound predicate binding and
logical necessity are not reliably established by this local verifier. A
larger original-goal review passing does not waive this failure. The full
autonomous goal-level replanning and CI-repair closure is still unfinished.

Reproduction with an existing isolated acceptance state:

```text
python tools/testing/verify_local_evidence_scopes.py --state <state> --endpoint http://127.0.0.1:18572/v1/chat/completions --model qwen3-4b-validation --output <new-report.json> --case compound-publication --case alternative-destination
```

`--recheck-report <retained-report.json>` performs separately recorded evidence
adjudication without new inference. It refuses to overwrite the original report.

## Automated checks

Latest focused checks: **89 passed**, covering field scopes, compound source
binding, causal regression scoring, checkpoint integration, local HTTP sampling
and streaming. In particular, malformed quotes, duplicate keys, wrong failure
fields, stale evidence, disabling during review, and premature completion are
not accepted as successful validation. These unit tests establish host behavior;
they are not a substitute for the failing live semantic controls above.

After fetching and integrating main `087da60bd`, the combined verification,
local context recovery, CI log tools and implementation-context selection
passed **133 tests**. Repository checks, whitespace checks, and 29 Desktop tests
also passed after integration. Desktop remains 1.1.6 rather than being downgraded
by the merge. Android changes from main were preserved, not installed or claimed
as device-tested in this run. These counts overlap the earlier selections.

An earlier broad development selection passed **174 tests**, including process
exit recovery at candidate intent (2,686.677 ms), commit (2,382.853 ms), and review
(2,002.185 ms). The completed real campaign was reopened and observed three times:
zero model calls, zero implementation starts, zero active workers, unchanged
completed graph. Focused and broad counts overlap and must not be added together.

Previously recorded checks for the preceding checkpoint increment:

- 122 campaign/checkpoint/integration/final-review tests passed.
- 76 candidate acceptance, source preservation and harness milestone tests passed.
- 29 Desktop tests and Desktop structure checks passed.
- Repository checks and whitespace checks passed.

These are focused selections, not a claim that the entire repository suite ran
locally. Earlier overlapping selections are not added to these counts.

The previous PR #2897 Windows backend job timed out after 30 minutes with 1,597
tests passing and no reported assertion failure. Its job limit was raised to
60 minutes in commit `3c78d7e7b`, without excluding tests or ignoring failures.
The next remote run completed with 2,420 passed, 12 skipped and one failed
timing assertion: elapsed time was 0.594 seconds rather than greater than the
intended 0.6-second sleep total. The test now measures only the request and
compares it with the actual 0.25-second socket inactivity timeout, excluding
server teardown. Six stream tests and 20 repeated active-stream runs passed.
This test-only correction was pushed to #2897 as `c45faeac1`. Its fresh complete
backend job now passed: **2,421 passed, 12 skipped, two warnings**, in 1,465.83
seconds. All reported checks for that head passed. The exact backend job is
[102006748128](https://github.com/galaxyssi/GalaxySSI/actions/runs/34209468719/job/102006748128).
Production timeout behavior is unchanged. This is the parent PR result, not a
claim that these counts include the new scoped-verification tests.

## Reproduction and boundaries

With an existing isolated acceptance state and a running loopback model:

```text
python tools/testing/verify_local_campaign_completion.py --state <isolated-acceptance-state> --endpoint http://127.0.0.1:18572/v1/chat/completions --model qwen3-4b-validation --finish
```

The harness rejects unfinished or changed campaign identity and does not restart
an already completed campaign. Raw evidence and failed attempts remain in the
isolated state's `completion-verification.json`, `completion-proofs/` and
`completion-attempts/`. The restart report is retained locally as
`build/completion-restart-evidence.json`.

Final acceptance here is an explicit coordinator harness operation, not an
automatically scheduled final-goal verifier. The separate base CI repair was
not performed autonomously by this candidate. No production scheduler was
enabled, no cloud model was used, and no phone or running Desktop was replaced.
