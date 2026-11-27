# Approved Capture Dispatch Persistence (Android #3007 Follow-up)

Integration follow-up: local combination with #4664 now uses its exact exported
revocation/Store-version normalizers when available. All capture assertions and
the complete non-pairing Store/coordinator comparisons are retained. No additional
capture production code is changed by this source-check compatibility update.

Reference: Android #3007 `65655f0c79c6ab04121150229a65b089180f82f2`,
MobileNativeAgentExecution's checkpoint/audit/final-input persistence before
external dispatch. Incremental base: main `43fa7602dad7ba6df27ac67c992421d5b25cf408`.

iOS resumes visible camera/microphone actions through a separate system-permission
continuation. That path previously ignored the task save result and bypassed the
planned-node journal. It now prepares the exact scoped input and active checkpoint,
commits the dispatched permission ticket and running plan through the existing
owned task-state CAS, then claims the encrypted node journal before execution.
Failure to prepare, save or claim cannot start a capture. A returned result whose
observation cannot be stored is not reported as verified success.

Preparation binds the original pending action, message, conversation, turn,
session, capture kind, permission ticket, input and host scope. A legacy authorized
capture without an active plan receives an execution envelope retaining the exact
pending queue; its dispatched ticket is rebound to the saved plan while keeping
the permission token and original action digest. No new action or permission is
invented. Existing plans retain their ID/revision and graph validation. Duplicate
callbacks and persisted dispatch intents cannot obtain fresh execution authority.

Queue follow-up (baseline main `c6bad3465c673dfb2dcecb23b095185c129c7447`): the
original single-action fallback lost later queued actions from the saved plan,
so subsequent captures/native tools could not prepare their checkpoints. The
envelope now retains action order and all original action data without planner
rewrites or connector-call deduplication. Only the current capture becomes running;
later actions retain their status and confirmation requirement. A second capture
uses the same plan but a new permission token and node/checkpoint identity.
An existing plan summary without its body, pending planning, blocked state,
wrong task/session ownership, duplicate/blank IDs, foreign scopes and already
dispatched legacy actions are rejected instead of receiving fresh execution proof.
This does not authorize the remaining queue or change its per-action gates.

Existing foreground/system permission, current permission-mode, read-only and
cancellation checks remain. Execution-paused and plan-only modes are also checked
before saving dispatch intent. Capture UIKit/AVFoundation surfaces, effect fences,
completion/attachment handling and general native executors are unchanged.
Captured bytes are not included in the task or journal fixture sources.

Task-state and node-journal writes are separate commits. A crash between them may
leave an intent without an operation; recovery conservatively does not auto-repeat.
A claimed node without a saved observation remains unknown, not proof of a failed
physical capture. Existing uncertain-effect recovery still applies. This is not
an OS background execution, cross-process CAS, fsync/power-loss, exactly-once or
instantaneous cancellation guarantee.

Twelve synthetic XCTest methods are authored, not executed: both capture kinds and
legacy no-plan preparation; persisted state visible before the synthetic effect;
cancelled/stale CAS; changed scope/input; plan-only/pause/revision/duplicate gates;
interrupted claim recovery; saved observation reuse; and failed observation storage.
Four queue follow-up methods cover both capture kinds with retained native/connector
actions; queue persistence before a synthetic first effect; a second capture with
independent permission and the original plan; and invalid legacy queue/summary gates.
The focused JS guard compares the whole coordinator outside this single method
against the baseline and freezes the permission, capture, journal and effect
kernels. The helper is separately frozen against the follow-up baseline except for the
single declared legacy-envelope block. Existing permission and ticket logic remains
byte-for-byte identical after restoring that block.
Structural checks do not prove Swift typing, native storage faults, camera/microphone
UI, actual permission races or device behavior. No native build/tests, full check,
CI monitoring, IPA or private evidence upload is performed.

Broader unplanned actions, browser and cloud-loop persistence, audit batching,
other Android #3007 work and the overall port backlog remain incomplete.
