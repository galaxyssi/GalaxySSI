# Android #3119: observed model-only connector failures

Android reference: `e7c6af6ef3eed21c7fb697b4458d1cf742833dc4`.
Independent main baseline: `8a794e82ebe8f09790e41139295ffb7ac1ee9701`.
This is a new known-backend-failure increment, not a duplicate active-observation,
transport-acceptance or storage change, and not full #3119 completion.

## Actual defect and integration

The queued iOS connector producer previously marked every post-start exception
as an unknown external effect, including pure on-device inference and cloud
generation errors before any tool attempt. Those waits could not reach the
existing committed-terminal failure/Auto recovery path.

A per-dispatch, exact-owner evidence object now distinguishes pure phone
inference from observed cloud generation. Phone inference must actually start;
cloud generation additionally requires the concrete stream engine to install an
observer for the normalized exact request ID. Tool execution marks possible
effects before dispatching any nonempty tool batch, including inline-generated
calls; it does not depend on whether the caller happened to consume a tool delta.
Legacy full-conversation delegation and default uninstrumented protocol adapters
also mark the boundary opaque. These flags are monotonic and lock-protected
across stream/tool queues; a repeated start or mismatched observer cannot reset
uncertainty. Evidence contains no prompt, credentials or new persistent schema.

Only actual model exceptions without an attempted/opaque tool boundary can
become a normal failed response. Task/CancellationError/URL cancellation and the
stream CANCELLED code remain excluded even after their message is wrapped.
Paired Desktop dispatch is never marked model-only and retains its original
unknown-outcome handling. Any attempted tool remains conservatively unknown;
this does not claim recovery of a partially executed tool workflow.

Known failures revalidate the original waiting/paused owned scope, then publish
through the existing encrypted response outbox, committed managed ledger and
response bus. The existing continuation still decides whether current policy
allows recovery. Manual locks, unknown/non-retriable metadata, action/run/contact/
conversation/turn/task/generation identity, privacy, admission and effect attempts
are not reset. There is no direct fallback dispatch, run-slot release, terminal
tombstone, fabricated success or response-ledger rewrite in the new policy.

Other stream users pass no observer and retain their original execution paths.
Protocol adapters implementing only the old overload remain source-compatible
but opaque: they cannot accidentally authorize model-failure recovery.

## Timeout audit correction

The pinned Android `MainActivityAgentExecution.kt.scheduleConnectorTimeouts`
returns immediately unless resource_location is desktop. Its pre-timeout helper
queries existing remote ownership instead of treating silence as rejection.
Therefore this increment does not add local/cloud timers or call the generic
iOS timeout helper just because historical port notes called it missing. Model
errors here are observed execution outcomes, not silence-generated failures.
Broader remote-silence/deferred discovery and other #3119 differences remain a
separate audit; no completion claim follows from this correction.

## Scope and verification

The source guard compares the complete coordinator and cloud stream engine
against main after removing only the declared evidence hooks. The original
protocol/transport, fallback, managed response, cloud tool-round and timeout
kernels remain unchanged. The dedicated new policy and eight synthetic XCTest
methods cover exact ownership, observation requirement, monotonic tool/opaque
boundaries, cancellation, matched committed settlement and retained recovery
restrictions. Fixtures are authored only, NOT executed.

Source/project/diff/i18n checks do not establish Swift type correctness, actual
tool/stream failure behavior, native persistence, privacy or concurrency/device
acceptance. No native build, XCTest execution, CI watching, Android/Desktop edit,
version bump or IPA is performed. No unmerged #4593-#4596 code is included.
