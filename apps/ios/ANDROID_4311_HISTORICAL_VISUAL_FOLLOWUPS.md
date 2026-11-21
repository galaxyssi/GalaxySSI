# Android #4311: historical visual follow-up completion

Source: https://github.com/galaxyssi/GalaxySSI/pull/4311
Android merge: `54f3f825a59f97426065c0aab49cc569378644ff`

## iOS mapping

- `AgentDirectVisionPolicy` distinguishes current uploads from historical image
  references. Historical-only turns do not instruct the model to restart the
  earlier image task. Questions requiring the original image still request
  native-pixel inspection, not reliance on an earlier assistant guess.
- `GalaxySSIServices.agentAttachmentExecutionGoal` puts the manifest and host
  vision guidance after the evidence boundary. Only the current user request
  feeds instruction-based routing.
- `AgentUntrustedEvidenceBoundary` repairs older iOS checkpoints containing the
  exact host-generated vision suffix before an attachment header. Ordinary user
  headers without an evidence marker and nonmatching user prose are preserved.
- Historical-only attachments no longer independently prohibit initial
  answer-only responses. New uploads retain the existing iOS attachment-reading
  route. Voice correction context does not turn old conversation attachments
  into a fresh execution obligation.
- `permitsAnswerOnlyResponse` is checked both when advertising the answer schema
  and when accepting it. Timer checkpoints, owned operations, phone actions,
  phone-runtime work, declared completion requirements, prior execution and
  continuation requests cannot bypass receipt review through a stale response
  flag. Existing outcome/artifact evidence admission remains unchanged.
- Parser diagnostics separately identify mixed completion/execution,
  invalid completion targets and completion before observations.

## Platform-specific behavior

Android's `MobileNativeAgentExecution` failure enum is not an iOS execution API.
iOS keeps its existing localized visual-delivery messages and structured planner
repair diagnostics rather than introducing unused Android failure codes. No
Android app/version files are modified.

## Verification scope

Added XCTest source for current/historical image guidance, legacy checkpoint
recovery, literal user headers, one-invocation explanatory replies, completion
diagnostics and retained timer/declared-work gates. XCTest, Xcode, simulator and
physical-device tests were not run on this Windows host. Targeted project,
whitespace and Swift grammar checks are static checks, not type checking or
runtime verification.
