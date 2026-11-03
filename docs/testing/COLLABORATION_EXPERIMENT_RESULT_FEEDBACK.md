# Experiment-result contract feedback

`experiment_result` represents a preregistered baseline/candidate comparison. It
does not mean any tool execution, search result or research report. A valid JSON
publication without an applicable saved `experiment_plan` must not be diagnosed
as malformed JSON or silently converted into a measured improvement.

## Feedback and member choices

Missing and non-object plan references report distinct codes at
`/body/experiment_result/plan`, with the observed shape and the expected exact
saved reference. Existing reference failures preserve their code, component,
expected/actual values and scoped reference facts, with the path contextualized
under the experiment result. An additive `record_contract` explains the purpose,
preregistration requirement and discoverable `foundation` rules. Storage errors
are not reclassified as member validation failures.

The existing publication recovery keeps the complete rejected draft, including
across store reopening. The member may inspect the saved contract, use an actual
applicable plan with its original measurements, preserve observational findings
as an ordinary artifact, or request coordinator assistance when an assignment
asks for an incompatible result kind. These are available choices, not a host
retry-count policy or automatic reclassification. The coordinator guidance also
distinguishes a reporting assignment from a prospective comparison.

No plan is invented or backdated, no completed tool operation is repeated just to
fill the type, and no acceptance requirement is relaxed. An ordinary artifact
does not satisfy an `experiment_result` requirement or authorize capability
retention. Original measurements, preregistration timing, access scope, independent
review and goal acceptance remain governed by the existing contracts.

## Verification scope

`CollaborationExperimentResultFeedbackTest` covers missing, null and malformed
references; wrong kinds and digests; inaccessible records; exact field facts;
storage exception propagation; complete draft recovery; member-chosen artifact
and assistance paths; actual-measurement and preregistration requirements; and
contract discovery. The existing evolution, record-validation, publication-
recovery and goal-acceptance suites provide regression coverage.

These checks use synthetic records. They do not establish that a real model will
select a better recovery strategy, acquire a new capability or finish a research
goal faster. No real-model acceptance is claimed for this increment.

On 2026-10-11, all 80 tests passed: 10 result-feedback, 22 evolution, 8 record-
validation, 13 publication-recovery, 7 protocol and 20 goal-acceptance tests.
The first test run found a test-fixture error that read a directory entry as a
full record; after switching to exact-version record retrieval, the complete
suite passed. The debug APK built as Android 1.4.146 (1231), including native
libraries and embedded-runtime verification. Kotlin source-size, Chinese-text
and diff checks passed. No phone installation, Desktop restart or model call was
performed for this increment. Desktop source is unchanged at 1.4.55.
