# Native Connector Deadline Observation Checkpoint

iOS-only continuation of Android #3119's stage-specific timeout observation,
referencing e7c6af6ef3eed21c7fb697b4458d1cf742833dc4 and
MainActivityConnectorTimeoutRecovery. Independent base:
c6bad3465c673dfb2dcecb23b095185c129c7447. This does not implement Android's
generic timeout/failover controller or claim full #3119 parity.

## Production Path

The active native connector wake already waited for the acceptance, running or
live-read-only timing boundary, but the corresponding task metadata was only
projected by the longer managed observation expiry path. At the actual due wake,
capture one deadline checkpoint in the original waiting result and plan action.
Use the same stage policy, legacy read-time anchors, attachment windows and clock
validation as the timer. Do not synthesize transport acceptance or remote status.

Before persistence, re-read the existing foreground/unlocked, profile, permission,
session, cancellation, exact action/result and managed-ledger ownership gate.
Require one matching action and its current last result, reconstruct the original
waiting envelope, then compare-and-commit the task. Retain phase, pending queue,
execution ownership and source identity. A failed or stale commit does not claim
success; a later owned wake can try again. The original recovery query sweep
remains responsible for all authenticated requests and final results.

Each stage/start/window clock is recorded once. Later polling does not turn the
same deadline into fresh evidence or repeatedly rewrite the task. Advancing
authenticated remote status clears the old deadline checkpoint along with the
existing observation hints. A new stage/anchor can later produce its own point.
The saved elapsed value is the checkpoint time, not a continuously updated age.

## Boundaries

This is a timing observation, not proof of remote failure, cancellation or an
external effect. Do not set awaiting_response=false, release a run slot, invoke
the failure resolver, select a fallback, replay a model/tool, retire the original
delivery, publish directly or invent a completion receipt. Terminal and user-wait
states do not receive a new stage checkpoint. Private/background/paused owners
remain excluded by the existing active observation policy.

The checkpoint is task-local encrypted state, not an atomic task/workspace/remote
transaction. Existing token/lifecycle improvements from separate PRs compose
without being duplicated here. No timer guarantee while iOS is suspended, native
socket/clock/fault acceptance, remote silence failover or arbitrary deferred
candidate discovery is delivered by this increment.

## Verification

Eight additional deliberately synthetic Swift fixtures describe stage boundaries,
attachment and live-data clocks, terminal/user-wait exclusions, one-point dedup,
legacy/malformed anchors, status advancement cleanup and metadata round trips.
They are authored in the existing registered test file, not compiled or executed.
Source contracts and project/whitespace checks do not prove native correctness.

No Swift/native build, XCTest execution, device/simulator/live model/network test,
full repository check, CI inspection, IPA, private evidence upload or remote
approval/merge is included. Android and Desktop sources and versions are unchanged.
