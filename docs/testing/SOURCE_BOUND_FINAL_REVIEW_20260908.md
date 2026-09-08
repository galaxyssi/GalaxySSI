# Source-bound final review experiment

## Scope

Desktop source version: 1.1.9. Android code is unchanged.

This is an opt-in replay implementation, not a production scheduler replacement.
The existing final campaign reviewer is unchanged. Private inference remains
restricted to a literal loopback endpoint; no cloud fallback is introduced.
No production evolution task, historical campaign, or GitHub publication is reset.

## Failure motivating this change

The initial combined source-partition/field-selection experiment returned the
entire original Chinese goal as one clause with 12 evidence fields. Its reviewer
then attempted to pass that clause using only the edited file. Host validation
rejected the result because the other selected fields were not quoted. The first
control was inconclusive after 614.5 seconds; the remaining controls were stopped,
not counted as passes. Raw observations remain in the local build directory.

This improves detection of incomplete evidence, but is not successful autonomous
verification. The earlier monolithic false-positive replay is documented in
`SCHEDULED_FINAL_VERIFICATION_20260908.md`.

## Experimental implementation

- Partition the complete original goal before revealing any evidence directory.
- Require exact, ordered reconstruction of the source, including whitespace.
- Select direct evidence fields separately, without revealing their values.
- Inspect each selected clause independently with exact, validated quotations.
- Preserve alternatives and conditions within their source clause.
- Exclude generated child requirements and historical acceptance verdicts from
  the direct evidence catalog. PR claims are metadata, not proof of file contents.
- Aggregate verdicts in the host: a later pass cannot overwrite a failure.
- Persist raw partition, scope, and field-review observations before validating
  them. Revalidate cached raw observations and bind them to source, fields, and
  reviewer configuration. Stop requests prevent subsequent inference calls.
- Expose named replay controls and preparation-only probes. Such reports are
  explicitly partial or preparation-only, never final acceptance certificates.

Exact source coverage does not establish semantic correctness. Model selection
of clause boundaries and evidence fields still requires real-model qualification.
Endpoint/model configuration identity is not a model-weights attestation.

## Verification

- 68 focused backend tests passed, including 21 original-goal review tests.
- Desktop checks: 29 tests passed and the structure check passed.
- The initial repository check found a non-i18n Chinese filename in the newly
  merged image-delivery report. Its English description now preserves the test
  result without embedding that localized filename; enforcement is unchanged.
  The full repository check passed after this documentation correction.
- SM-T575, installed Android 1.1.4 (890): three result-recovery instrumentation
  tests passed (corrupted pages rejected; transport receipt does not imply durable
  consumption; large reply persists across database reopen and duplicate delivery).
  These use isolated databases and simulated transport, not a real Provider or
  device-reboot acceptance test. Existing user conversations and pairings are retained.

## Real local preparation probe

Qwen3-4B-Instruct-2507 Q8_0 was served on literal loopback using a temporary
llama.cpp server. The read-only harness checked the immutable Git contents and
GitHub publication before and after the probe; publication metadata was unchanged.
The server was stopped afterward. No cloud model was used.

| Probe | Time | Observed preparation |
| --- | ---: | --- |
| Original full Chinese goal | 367.594 s | Four losslessly reconstructed clauses |
| OR with one true branch and a target-branch requirement | 66.890 s | One joint clause, with title, body and target branch selected |

These are preparation observations, NOT two passing acceptance tests. The
original goal's preservation clause selected only `changed_paths`, which cannot
establish unchanged existing contents. Its independent-verification/publication
clause selected PR title, body and URL but no independent execution evidence.
The reporting-honesty clause selected only PR body, which cannot by itself prove
that reported validation actually occurred. Thus this preparation is not
qualified for production final acceptance even though its source coverage and
schema checks passed. The OR expression was not split into mandatory branches,
but no live verdict was obtained for either OR truth assignment in this probe.

Raw observations are retained locally in `build/source-parts-v2-preparation.json`.
The full final-review control matrix has not been rerun with this implementation.

## Remaining acceptance

The source-only preparation probe is not final review. Full live controls must
still reject missing requested file content, wrong publication language, and
missing publication evidence while accepting a valid original goal and a valid
OR branch. Both-false OR evidence must fail. Reasons and quoted fields must also
be correct; a failure for the wrong reason is not qualification.

Only after that qualification should the scheduler adopt the new reviewer,
invalidate the old review contract, and prove persisted recovery and complete
autonomous publication/CI repair. This change does not claim that full closure.
