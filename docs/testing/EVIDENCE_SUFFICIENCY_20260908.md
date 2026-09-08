# Original-goal evidence sufficiency experiment

Desktop source version: 1.1.10. Android is unchanged. This extends the opt-in
replay from PR #2905, not the production final-verification scheduler.

## Framework mechanics

- Independently inspect each source clause's evidence selection without exposing
  candidate values or selector explanations to the audit model.
- Preserve raw audit responses before validating exact clause coverage, typed
  decisions, evidence references, and contradictory sufficiency claims.
- An insufficient clause becomes `awaiting_evidence` with concrete missing-field
  references and an explanation. It cannot grant final acceptance.
- On resume, retain the original source partition and send the last insufficient
  selection and its audit to evidence replanning. Never rewrite the original goal.
- Previously valid, unchanged clause reviews may be reused; cached raw audits and
  selections are revalidated. Contract revisions invalidate older proof formats.
- Preparation-only replay can audit a previous preparation against identical
  immutable control evidence, without regenerating the compiler's output.

## Automated verification

- 78 focused backend tests passed, including 23 original-goal review tests and
  eight sufficiency-audit tests. Counts overlap earlier reports; do not add them.
- Desktop: 29 tests and the structure check passed.
- Repository and whitespace checks passed.
- No new APK, Desktop installation, or phone test was performed for these changes.

## Real model result: not qualified

The existing Qwen3-4B-Instruct-2507 Q8_0 local endpoint audited the exact saved
preparation from `SOURCE_BOUND_FINAL_REVIEW_20260908.md`. The historical proof,
immutable Git content, and unchanged GitHub publication were checked by the
read-only replay harness. No cloud inference or production evolution was enabled.

| Control | Time | Result |
| --- | ---: | --- |
| Original Chinese goal with known insufficient scopes | 483.391 s | Incorrectly marked every clause sufficient |
| Joint OR expression with title, body and base-ref fields | 30.969 s | Marked sufficient; this is not an OR truth-verdict test |

The first result is a real failure, not a passing acceptance test:

- It incorrectly treated a changed-path list as proof of original content preservation.
- It incorrectly treated PR title/body/URL as proof of independent validation.
- It asserted unseen PR-body content even though the audit received no field values.

The host's schema/reference checks accepted this well-formed but semantically
incorrect audit. Therefore adding an audit prompt alone is NOT a demonstrated
solution to the real verification failure. These experimental changes must not
be presented as qualified autonomous final acceptance or enabled on that basis.

Raw observations remain local in `build/source-sufficiency-live.json`.

## Deferred model comparison and remaining work

A separate Qwen3.5-9B Q5_K_M download was stopped at the user's request before
completion. The model was not loaded or tested; no claim is made about whether
it would improve these results. Larger-model testing is deferred.

Remaining work includes reliable evidence selection and verification with the
available model, complete positive/negative and conditional-control verdicts,
actual recovery-driven replanning, production integration, and full autonomous
publication/CI-repair acceptance from the tablet. Framework unit-test success
does not establish any of those end-to-end outcomes.
