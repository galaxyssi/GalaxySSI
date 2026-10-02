# Semantic goal coverage and qualified acceptance: bounded phase

Worktree base: `9ddda0316`. Changed files (under `apps/android/app/src` unless noted):

- `main/java/com/galaxyssi/chat/CollaborationGoalAcceptance.kt`
- `main/java/com/galaxyssi/chat/CollaborationGoalLoop.kt`
- `main/java/com/galaxyssi/chat/CollaborationReviewContract.kt`
- `main/java/com/galaxyssi/chat/CollaborationSemanticGoalCoverage.kt` (new)
- `main/java/com/galaxyssi/chat/CollaborationQualifiedValidator.kt` (new)
- `test/java/com/galaxyssi/chat/CollaborationGoalAcceptanceTest.kt`
- `test/java/com/galaxyssi/chat/CollaborationReviewContractTest.kt`
- `test/java/com/galaxyssi/chat/CollaborationSemanticGoalCoverageTest.kt` (new)
- `test/java/com/galaxyssi/chat/CollaborationSemanticGoalLoopTest.kt` (new)
- `test/java/com/galaxyssi/chat/CollaborationQualifiedValidatorTest.kt` (new)
- `androidTest/java/com/galaxyssi/chat/CollaborationGoalAcceptanceDeviceTest.kt`
- `androidTest/java/com/galaxyssi/chat/CollaborationLiveEvidenceDeviceTest.kt`
- `docs/development/SEMANTIC_GOAL_COVERAGE_PHASE.md` (this document)
- `docs/testing/COLLABORATION_LIVE_EVIDENCE.md`

## Scope and trust boundary

New `CollaborationGoalAcceptance.evaluate` calls require a saved original-goal
mapping and a separately authored typed review. The host verifies exact text
coverage, preserved criterion bindings, revision integrity and reviewer identity.
It does **not** establish that a model's interpretation is objectively complete
or scientifically true. A dishonest or mistaken independent semantic judgment
can still be wrong. Coverage is a required audit trail, not a semantic oracle.

GoalLoop prompts and continuation binding preservation are integrated. The Android
worker now publishes an immutable, paged goal contract before dispatch and exposes
member-scoped recall to cloud/native executors. Workspace ancestry and independent
review integrity checks are integrated; adaptive recruitment remains a separate
workstream. Existing checkpoint receipts retain their original
meaning; this phase does not silently recertify historical results. New evaluations
without the mapping fail closed with repair feedback.

## Mapping and review protocol

The assessment supplies `goal_coverage.mapping` and `goal_coverage.review`, each
an exact workspace `{object_id, revision, sha256}` reference. After the first plan,
GoalLoop supplies a host manifest through the existing acceptance-feedback channel
to every member. It contains stable `source-N` IDs, exact source text, the raw UTF-8
original `goal_sha256`, and a canonical preserved `criteria_sha256`. Models copy
IDs/hashes; they never count offsets or reproduce the source/criteria as proof.
The mapping is an `artifact` whose `body.semantic_goal_mapping` contains:

```json
{
  "format": "galaxyssi.semantic-goal-mapping.v1",
  "goal_sha256": "copy the host original-goal hash",
  "criteria_sha256": "copy the host preserved-criterion hash",
  "segments": [
    {"id": "source-1", "criterion_ids": ["comparison"], "rationale": "Maps the requested comparison"}
  ]
}
```

Host source v1 uses mechanical line/punctuation boundaries and bounded-length
slices, preserving whitespace and surrogate pairs. Concatenated source text equals
the entire nonblank original goal; these slices are not semantically extracted
requirements. Every host ID and criterion must be mapped; unknown, omitted or
duplicated IDs and model-supplied replacement text/offsets are rejected. Criterion
bindings include requirement, verification, required observation origin/tool pairs
and any qualified validator specification. Status and delivery references are not
part of this mapping binding because they change as work completes.

The independent `acceptance_review` object uses `body.semantic_coverage_review`
instead of `body.acceptance_review`. It supplies the exact mapping `target`, a
`verdict`, `rationale`, `unresolved` array and a `segments` array. Every segment
review repeats its exact `id` and `criterion_ids`, with its own verdict, rationale
and unresolved array. Completion needs all verdicts `supported` and all unresolved
arrays empty. Negative/untested reviews remain publishable. Review `parents` must
cite the mapping. Reviews cannot combine the two review payloads in one object.

The acceptance gate resolves both current revisions in the same run/turn and
checks every mapping contributor against the review author. The evaluating coordinator
also cannot be the coverage reviewer. Forged, inaccessible,
tampered, stale or self-reviewed mappings cannot issue a successful receipt.
Existing delivery, independent review and host-observation checks still apply.
Two people suffice: the coordinator/author publishes the mapping in an EXECUTE
job, then the peer independently reviews it in VERIFY work. The same peer may
review the delivery in a separate object. The reviewer must not author the mapping;
no third person or relaxation of independence is needed.

## Qualified computational fixture

The closed host validator interface has one concrete implementation:
`exact_integer_sum.v1`, qualified only for `computational` exact integer addition.
An earlier preserved criterion supplies:

```json
{
  "requirement": "Compute the exact integer sum: 2 + 3.",
  "verification": "computational",
  "evidence_kind": "observed",
  "validator": {"id": "exact_integer_sum.v1", "operands": ["2", "3"]}
}
```

Its saved delivery includes substantive `body.content` and
`body.computation: {"validator_id":"exact_integer_sum.v1","result":"5"}`.
The host recomputes using `BigInteger`, with 2..32 canonical decimal operands of
at most 256 digits each, and compares the exact canonical result. The requirement
must equal the literal operation description generated from those operands.
Broader computational/scientific claims cannot borrow this qualification.
Preserved validator inputs (including their absence) cannot be changed, removed
or added during continuation or completion; establish them in the first criterion.
The computation is local, bounded and side-effect-free; no tool/model request or
external experiment occurs. Existing independent delivery review remains required.

Unknown validators and all physical domains fail closed. Simulation/proposal
evidence never counts as observed acceptance. No physical validator is registered;
adding one would require independently qualified measurements, scope, calibration,
uncertainty and authorization checks, not a model-selected adapter name.

## Integrated contracts and verification

GoalLoop and ReviewContract both include the mapping instructions. GoalLoop
decode/disposition/merge reject changed or malformed validator specifications;
rejected merges retain the original criterion. Malformed persisted criteria remain
unchanged instead of becoming an empty contract. They block automatic/model repair
dispatch until authorized recovery restores the exact trusted contract; they do not
enter an infinite coordinator retry loop. Valid contracts with invalid proposed
assessments still dispatch a coordinator-only repair. Every continuation regenerates
the source/criterion manifest in acceptance feedback, not member assignment intent.
No Runtime hook is outstanding. Seeded direct-start fixtures use
`CollaborationGoalLoop.acceptanceContext(goal, criteria)` for the same host context.
Source v1 and its segmentation must be versioned together if changed after release.

Device fixtures now seed two-person mapping/review records. The opt-in live fixture
asks the coordinator/author for the mapping and the peer for two separate reviews;
it checks their exact identities and final references. It still verifies documentary
command provenance, not general computational/scientific completion. Prior recorded
live passes do not establish that this new mapping contract has passed.

Adversarial JVM tests are added in `CollaborationSemanticGoalCoverageTest` and
`CollaborationQualifiedValidatorTest`, plus `CollaborationSemanticGoalLoopTest` for
continuation preservation, corrupt contracts and two-person planning. Existing acceptance fixtures supply real
saved mapping/review revisions. ReviewContract tests cover separate typed reviews
and contradictory verdicts. Parent should run these plus existing acceptance,
review, goal-loop, evidence and workspace regression suites sequentially.

The initial parent integration passed 54 focused JVM cases. The first expanded
regression ran 397 cases, with 396 passing and one outdated schema expectation
failing after adding `goal_contract`; that expectation was corrected. Final results
are recorded separately after rerunning the completed patch. The application APK
built during that run; this does not certify subsequent edits or device behavior.

Long goals and optional context are archived verbatim and paged through the exact
dispatch binding. The 32,000-character initial prompt reserves the complete current
assignment and response protocol, omits optional records only as whole records and
points to their durable originals. Retry pins include raw criterion JSON as well as
canonical requirement bindings. Reads do not register delivery/comprehension.

### Android 1.4.20 local verification

The final integrated selection passed **446 JVM tests across 38 suites**, with
zero failures, errors or skips. Both APKs built. Android **1.4.20 (1105)** was
installed on the authorized S26U without clearing data. **17 local instrumentation
cases passed in 112.042 seconds**, including cloud/native full-goal paging,
member revocation, independent coverage, exact observations, existing goal
continuation and original archive retrieval. A separate two-process recovery
pair passed for a 51-page snapshot, including a 100k-character goal, 21k-character
criterion and retained contexts; process IDs were 16706 and 16848.

After a real-provider attempt exposed managed stream framing, two additional JVM
policy checks and four loopback-only S26U stream cases passed. The latter completed
in 6.822 seconds and cover tool-round prefaces, direct final output, interrupted
streams, ordinary-chat streaming and collector cancellation. The first cancellation
fixture incorrectly throttled request uploads as well as response output; applying
the response throttle only after dispatch corrected the fixture without changing
production cancellation or extending its deadline.

The first 444-case pass exposed two test-only defects: a legacy repeated-scan
expectation and a missing member identity in the prompt fixture. Both were fixed
without relaxing access checks. The first device pass exposed a fixture that
removed its coordinator without assigning the remaining member; correcting that
fixture made the full selection pass. Failed attempts are not counted as passes.

The 150 KiB Kotlin size gate and whitespace checks passed. The repository-wide
check still fails existing i18n findings in unchanged files. The opt-in updated
real-provider fixture is tracked separately in the live evidence document.

One strict new-contract real-provider fixture passed in 328.873 seconds after the
managed framing repair; the earlier failed attempt is retained in the live record.
It verifies one documentary task, its exact-original peer read and separate goal
coverage review, not a general semantic or scientific result.

Broader semantic reliability, source relevance/consumption, scientific correctness,
physical qualification and real-provider stability remain unverified.
Multipart semantic mapping/review unions for goals larger than a model's usable
context are not implemented. Paging preserves access to originals; it does not by
itself prove complete understanding of an arbitrarily large goal.
