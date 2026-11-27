# Reviewed Team Drafts and Decimal Comparisons (Android #4644)

Baseline: Android PR #4644, merge `dd34ab706de214a56e48b6b24b96802b73f170cb`.
Follows the iOS #4640/#4642 ports. iOS only; this does not include subsequent
mandatory-review, model-authored-editor or other Android team changes.

## Final Draft Editor

For a host-numbered plan, the last reviewer without downstream consumers is
reserved as the final editor. All other roles execute in the existing bounded
graph. After synthesis, the editor receives the original complete objective,
its assigned direct parents' public reports and the actual synthesized draft.
It is not asked to endorse an earlier partial result.

An exact typed verdict can accept the draft, revise it with a visible objection
and complete changed answer, or withhold publication with a bounded reservation.
Malformed, ambiguous, unchanged revisions, cancelled or incomplete audits do not
return a successful outcome. Corrections and pre-existing independent dissent
remain visible. The editor consumes an allocated role: ten roles, three parallel
workers and twelve total logical calls remain the limits. UI receipts count the
editor as a role; progress includes a metadata-only auditing stage.

Named legacy plans retain their explicit pre-synthesis reviewer graph semantics.
Reviewers with downstream consumers also remain pre-synthesis. As in the Android
baseline, a plan without an eligible final editor does not gain a host-invented
reviewer or extra model call. Later review-policy PRs are separate work.

## Explicit Source Tables

Only one explicit Markdown table with `input | gate` (or localized Chinese
headers), 1-10 unique series, 1-32 unique rows, complete separators, and at least
one threshold qualifies. Each threshold must be `<`, `<=`, `>` or `>=` against a
canonical printed decimal; `-` means that row has no threshold. Missing values,
units inside numeric cells, exponent notation and ambiguous layouts are not
inferred. Numerals have at most nine integer and nine fractional digits.

The host compares Foundation Decimal/NSDecimalNumber values without binary
floating-point rounding. Evidence preserves each original numeric string, row
verdict and the ordered set of series passing every gate. The planner receives
a compact table representation; workers still receive the full original source.
Synthesis and final audit receive verified table evidence.

When an allocated editor audits a recognized table, it must return exactly the
verified passing set, a purpose and an evidence limitation. The app prints the
original table and deterministic passing result, not the model's draft verdict.
Incorrect, duplicate or missing winning series produce a mismatch receipt with
only the deterministic table result. Model agreement is not measurement,
scientific feasibility, safety or clinical benefit.

Only the exact table-audit system prompt on a literal loopback OpenAI-compatible
endpoint may request shape-only JSON-schema decoding. It supplies no winner enum
or answer. Other prompts/providers/hosts retain their existing request format.
Existing credential, disclosure, transport and endpoint policies are unchanged.

## Verification Boundary

Thirteen new synthetic XCTest methods are authored: five table cases and eight
audit/engine cases. These cover strict/inclusive decimal boundaries, label swaps,
invalid tables, source-set mismatches, visible revisions, withholding, cancellation,
legacy semantics and the 12-call allocated-editor limit. They are not executed.
Focused JS source contracts and the iOS project structure check are used instead.
No Swift build, XCTest execution, live model acceptance, simulator/device test,
scientific validation, full repository check, CI monitoring or IPA generation is
claimed. Android's native and model experiments are not iOS test evidence.
