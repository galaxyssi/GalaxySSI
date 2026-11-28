# Native Model Loop: Swift Task Cancellation

iOS-specific execution-lifetime correction found while continuing the Android
#3007 comparison. Independent main base:
`c6bad3465c673dfb2dcecb23b095185c129c7447`. This is not a claim that Android
uses Swift task cancellation or that the wider Android port is complete.

## Production Correction

The native model tool loop previously observed its explicit cancellation token
only. Cancelling its Swift Task without also cancelling that separate source
could leave later model rounds and native tools running. Adding Task.isCancelled
inside native worker hooks alone would not fix it: DispatchQueue workers do not
inherit Swift task-local cancellation.

Each LoopState now owns one existing lock-protected cancellation source. Its
request token ORs the original token with that source. The initial advance and
approval-resume execution install Swift task cancellation handlers that cancel
the same source. Existing model requests, terminal guards, retry boundaries and
native registry checkpoints therefore see the signal, including native workers.

The combined token strongly retains the source across an approval pause. Normal
completion of the pausing task does not cancel an approval; resuming it installs
a handler for the new caller task without replacing or clearing earlier signals.
The existing approval nonce, consumption, expiry and consent rules are unchanged.

No model/tool replay, new grant, retry permission or journal schema change.
Cancellation still uses the existing loopCancelled event and checkpoint. This
does not forcibly terminate synchronous code, interrupt an adapter that never
checks cancellation, retract already-sent bytes, or undo an external effect.
Setup/catalog/journal reads before the advance handler remain unchanged.

## Verification Boundary

Six Swift fixtures are authored but NOT compiled or executed: pre-cancelled run,
cancelled model response before tools, a native checkpoint on a DispatchQueue,
pre-cancelled approval resume, uncancelled approval across tasks, and cancelled
state retained across a new loop instance using the same in-memory journal.
They are not durable-disk, real provider, approval UI or thread/race acceptance.

The source tool freezes exact production/fixture deltas, preserves the older
ownership increment when installed, and rejects eleven synthetic source mutations.
No Swift build, XCTest, native/model/network/device execution, CI monitoring or
IPA is included. Full cancellation/recovery and Android parity acceptance remain
open.
