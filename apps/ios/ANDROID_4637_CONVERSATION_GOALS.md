# Conversation Text Goals

Ports Android #4637 (`aa71666b2395ce647d9af3566899c7862b481422`).

`/goal` commands open a conversation-bound panel for starting, inspecting,
pausing, resuming with clarification, or stopping a text goal. Start/resume
requires explicit selection/confirmation of an on-device or direct cloud model
and authorizes at most six additional rounds, including review. Paused tracking,
private, group, merged, inactive and unrelated scoped conversations are excluded.
Attachments and screen-analysis sessions cannot enter this path.

## Execution and Recovery

- Encrypted per-profile/per-conversation checkpoints pin the objective and route,
  including local profile metadata or the cloud model/endpoint/API style binding.
  Compare-and-replace checks reject old runs, generations and revisions.
- Persist a round claim before submitting a model request. An uncertain in-flight
  request after interruption becomes blocked, never an automatic replay.
- Supply only the objective, bounded checkpoints, pending step and clarification.
  No tools, health records, other chat history, session/global requirements or
  paired Desktop delegation are provided. Tool declarations are removed from
  cloud request bodies; tool-call output is rejected rather than executed.
- A proposed final result requires another model request with separate final
  review instructions. This is the model's internal text review, not independent
  proof of external actions or real-world facts. Objectives requiring missing
  evidence/actions must block. Repeated output and malformed results block too.
- Each accepted stage is committed before delivery, using a stable receipt ID.
  Recovery also publishes committed terminal states without rerunning inference.
  Handoff retains the first and latest fifteen stages; delivered chat stages are
  not removed by that model-context bound.
- Pause/stop advance generation and cancel the active task. Identity, conversation,
  route and exact stored-claim checks fence late callbacks. Cancellation is
  best-effort and cannot recall a request already received by a provider.

## iOS Background Boundary

Foreground execution can finish its current system background grace period.
Persistent work also registers a BGProcessing task with typed Info.plist
identifiers, preserving existing background modes and task identifiers. A cold
launch restores the existing encrypted app state, not a new goal or identity.
Slices are bounded; expiry/protected-data loss cancels work and preserves the
uncertain-request fence. iOS chooses when to grant background time, and may not
grant it promptly or after force-quit. The interface does not promise continuous
Android WorkManager-like execution. The next app/system opportunity can continue
confirmed idle checkpoints without extending their round allowance.

Session deletion tombstones goal rows; private-data erasure removes encrypted
rows and their key material and cancels background intent. The panel clears
sensitive state on profile/conversation changes, backgrounding and privacy lock.

## Verification Boundary

Focused JS contracts check source wiring, scope fences, registration and resource
placement; `npm run check:ios` checks project structure. Twenty synthetic XCTest
methods are authored but unexecuted. No Swift/native compilation, live provider,
device/background execution, full repository check, CI monitoring or IPA build
is claimed. Those remain release verification requirements, including inspecting
the built Info.plist array and exercising system expiry on a device.
