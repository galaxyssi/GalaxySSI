# Android #4587: Verified Timer Starts

Pinned reference: `be25c59d487f35d3df1732cf1fd9a2e51e160642`, nine changed
files with hashes/dispositions in ANDROID_4587_PORT_COVERAGE.json.
iOS baseline: main `9781cd99a1ad53c7408a664f1a3b4ebb27579f3e`, after
synchronizing merged #4588. That prior resumed-model change is not part of this
increment's diff against main.

## Production Integration

The actual timer producer now includes its immutable duration and local execution
authority in evidence. Successful notification readback still supplies the
existing completion_verified flag; submission alone, an unavailable readback,
missing notification or unknown dispatch cannot qualify. No Android-only
business-success flags are invented for iOS.

The shared model prompt documents nested target/parameters arguments. The real
model parser retains only a literal boolean action.completes_goal=true, in an
internal planning parameter. It is not a permission or receipt. Reuse the existing
iOS anchored duration interpreter for exact full timer/duration requests. Other
wording requires the model declaration, as on Android; this does not claim full
Android duration-language equivalence or that model semantic judgments are proven.

The native finish path compares the exact active node/input with its successful
native receipt, running state, nonblank operation identity and requested duration.
Require observed completion requirements and no unresolved host effects. Reject
additional answer/publication/file/Linux requirements and other remaining work.
Only a supervised reviewer whose sole dependency and output source is this timer
may be pruned; running/failed reviewers cannot be discarded. A qualifying start
uses the existing final-message/task writer and does not request another rolling
model batch. A later inspection/pause/resume/cancel/replace is not a start.

The actual interruption and pending-connector-resume paths attempt timer recovery
first. Check foreground/protected-data/transcript, current session and cancellation
scope, then read the exact existing sequential node-journal receipt. Do not invoke
a tool, plan another task or send a timer command. Unknown/unreadable/unverified
records retain the prior recovery path. Old waiting reviews must match exactly
the two-node timer/reviewer plan and its waiting action ID.

Legacy iOS receipts lack duration and authority. They require the existing native
executor provenance plus the original successful running receipt and a matching
immutable operation ID/source-turn/duration checkpoint. The checkpoint alone is
not evidence of running state. Original journal output is not rewritten. Missing
or replaced legacy identity stays pending; no duration or proof is guessed.

iOS multi-action parallel native batches exclude connector reviewers; a timer
plus unrelated native work must not close that batch. No unused parallel terminal
implementation is added. Existing journals, dispatch/consent, retries, transport,
notification I/O and final-message persistence kernels remain unchanged outside
the declared hooks. Existing final writes are not a new atomic cross-store
transaction. A previously sent remote reviewer is not cancelled by a new wire
command; its removed native wait cannot resume a completed task.

## Verification Limits

Eight new Swift fixture methods and one parser fixture are authored and registered,
NOT compiled/executed. They cover exact English/Chinese goals, extra work and
failures, wrong receipts/operations, legacy identity/provenance, journal reopen
without redispatch, actual notification-backed producer and literal declarations.
They do not execute Coordinator foreground recovery, notification delivery,
restart/privacy/UI behavior or a real timer on a phone.

The source guard pins all reference files and compares surrounding production
against the stated baseline after only explicit completion/recovery/metadata/
prompt hooks. No native build/typecheck/XCTest, CI monitoring or IPA. Source
checks are not native, model compliance, persistence-fault or device acceptance.
The wider Android-to-iOS backlog remains incomplete.
