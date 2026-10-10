# Collaboration recipient contract

## Scope

Android 1.4.125 / code 1210 corrects model-facing recipient guidance used by both
cloud workers and delegated Desktop workers. No Desktop source change is needed.
The running research runtime is not replaced by this change.

The supplied roster contains authoritative member identifiers. Those identifiers
are opaque strings; UUID syntax is not required by the existing validator.
Several model-facing contracts incorrectly called them UUIDs, allowing a worker
to conclude that a valid non-UUID roster could not be used for a directed question.

Use consistent guidance in the research artifact contract, current and legacy
member prompts, dynamic plans, recruitment, learning agendas and candidate review:

- Copy the exact member ID from the roster into `requests[].to`.
- Never manufacture a UUID or substitute an inferred display name.
- A coordinator request and an addressed peer request are distinct operations.
- Publish exact workspace versions alongside a peer request; availability does
  not imply that the peer has read, adopted or verified them.

This changes instructions, not routing authority. Recipient enrollment, explicit
producer selection, independent-review isolation, exact-version grants, replay
and cancellation behavior remain unchanged. There is no new broadcast, nickname
fallback, model invocation or tool permission.

## Regression coverage

`CollaborationResearchArtifactTest` checks structured-stage instructions and
acceptance of short, namespaced and UUID roster IDs without rewriting them.
The final delivery stage continues to request Markdown rather than request JSON.

`CollaborationPeerUpdatesTest` exercises actual publication/read grants with
those three ID forms, verifies that an unaddressed member cannot read a result,
and distinguishes a coordinator-only request from a later addressed peer offer.
Existing tests cover independent review, durable replay and exact observations.
`CollaborationResearchPromptTest` covers all research stages and planner/controller
roles under a large input, preserving exact-ID guidance and the existing original
goal/context budget. Identity wording is shared without duplicating the full
recipient explanation in the common prompt section.

## Validation

186 JVM tests passed with zero failures, errors or skips in these suites:

- `CollaborationResearchArtifactTest` (8)
- `CollaborationPeerUpdatesTest` (10)
- `CollaborationDirectedDiscussionTest` (6)
- `CollaborationMilestoneTest` (14)
- `CollaborationMilestoneProtocolTest` (5)
- `CollaborationPublicationProblemTest` (2)
- `CollaborationResearchPromptTest` (24)
- `CollaborationGoalRecruitmentTest` (13)
- `CollaborationLiveGraphTest` (24)
- `CollaborationLearningTest` (13)
- `CollaborationCandidateEvolutionTest` (51)
- `CollaborationSemanticGoalLoopTest` (16)

The first build could not locate the independent Rust native-memory toolchain.
The JVM run used the repository's existing `-x :app:buildNativeMemory` and
`-Pgalaxyssi.requireEmbeddedRuntime=false` options. No native code changed.
This validates Kotlin compilation and the scoped unit tests, not native packaging
or an installed APK. An initial new-test failure incorrectly expected JSON
instructions from the Markdown-only delivery stage; the test now verifies that
the existing delivery behavior remains unchanged.

The expanded run caught duplicate guidance displacing a long original goal.
The common identity explanation was shortened, without increasing prompt limits
or weakening the existing goal-retention test. The final full run above passes.
`node tools/quality/check-kotlin-source-size.mjs` and `git diff --check` also pass.

No real-model improvement or device installation is claimed by these local
contract tests. The frozen running product and experimental inputs are unchanged.
