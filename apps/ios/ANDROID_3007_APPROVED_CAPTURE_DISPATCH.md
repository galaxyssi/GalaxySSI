# Approved Capture Dispatch Persistence (Android #3007 Follow-up)

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
capture without an active plan receives a single-action host plan containing only
that same action; its dispatched ticket is rebound to the saved plan while keeping
the permission token and original action digest. No new action or permission is
invented. Existing plans retain their ID/revision and graph validation. Duplicate
callbacks and persisted dispatch intents cannot obtain fresh execution authority.

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

Eight synthetic XCTest methods are authored, not executed: both capture kinds and
legacy no-plan preparation; persisted state visible before the synthetic effect;
cancelled/stale CAS; changed scope/input; plan-only/pause/revision/duplicate gates;
interrupted claim recovery; saved observation reuse; and failed observation storage.
The focused JS guard compares the whole coordinator outside this single method
against the baseline and freezes the permission, capture, journal and effect
kernels. Structural checks do not prove Swift typing, native storage faults,
camera/microphone UI, actual permission races or device behavior. No native build/
tests, full check, CI monitoring, IPA or private evidence upload is performed.

Broader unplanned actions, browser and cloud-loop persistence, audit batching,
other Android #3007 work and the overall port backlog remain incomplete.
