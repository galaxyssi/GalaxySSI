# Android #3119: pre-shadow candidate preparation

## Scope

Android reference: `e7c6af6ef3eed21c7fb697b4458d1cf742833dc4`,
`AgentResourceRouter.kt`. Its self-model calibration precedes the six-alternative
domain-aware limit, and quality observation operates on that bounded decision.
This increment starts from main `f2b671fa9a9728bfc6e1c94697bec0bdf89c943e`,
including the reported-usage work merged in #4577.

The iOS connector selector now captures one self-model snapshot, calibrates each
unique eligible ordered candidate once, sorts stable score ties, preserves an
admitted explicit preference, and applies the existing domain-aware six-fallback
policy before quality routing. Quality promotion retains that bounded ordering;
there is no second calibration or domain re-sort after promotion. Catalog entries
alone cannot fabricate admitted candidates. Real disconnected reasoning candidates
retain the existing recovery diagnostic.

An internal baseline-score reason preserves the original integer score so a reused
decision replaces its old calibration instead of compounding it. Checked addition
clamps at integer limits; quality baseline normalization converts to Double before
adding its offset. Normal-range quality policy behavior is otherwise unchanged.

Healthy stable-primary fast paths, eligibility, capability/health admission,
reported usage, session privacy filters, budgets, deadlines, executor ownership and
provider-health mutation rules are retained. The project source check now requires
the actual preparation hook instead of a removed fabricated-fallback reason.

## Evidence and limits

Ten XCTest fixture methods were authored and registered in the Xcode test target;
they were not compiled or executed. JS/source-contract checks and project/diff
checks are not native, runtime, performance, privacy or security acceptance.
No IPA, native build, XCTest execution, CI monitoring, approval or merge is part
of this change.

Desktop cost ingestion was investigated but is not implemented here: gateway
token/cost estimates are explicitly estimated, and the scoped provider journal
exposes observed-notifications-only coverage with unknown billed cost. They must
not be relabeled as actual billed usage or used to invent a new wire protocol.
The existing optional reported-cost schema still has no production cost writer.

This is one bounded #3119 increment, not completion of all #3119 features or the
Android parity backlog. Native validation and broader integration remain open.

Project structure, JavaScript syntax, diff whitespace and the pre-shadow, usage,
health, provider-resource ranking, connector observation, research provenance,
autonomous/research source, background cognition and live-planning source checks
passed. Two older historical scope guards still fail outside this increment:
stable-auto admission expects an older model-picker layout; planning-context
timing expects an older retained-prewarm service hook. The relevant model-picker
and services implementations are unchanged from the current main baseline.
These failures are disclosed, not waived or reported as passing.
