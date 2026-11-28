# Cloud Tool Invocation Journal

Independent iOS follow-up from the Android #3007 checkpoint-before-execution
comparison, based on main c6bad3465c673dfb2dcecb23b095185c129c7447. This is the
actual CloudConversationStreamEngine tool path, not the separate native model
loop. It is not full Android parity or a complete cloud round/session restorer.

## Implementation

Reuse AgentModelLoopJournal and its existing encrypted store, immutable writes
and process-local leases. Each provider request/round/slot is scoped to the
profile, contact, conversation and turn. The pre-execution input record binds
the serialized provider-request fingerprint, collaboration owner, exact call ID,
tool name and parsed arguments. Changing these inputs in the same slot fails
closed; it does not allocate a second claim under an input-dependent key.
Scope IDs are hashes so arbitrary identifier lengths cannot trip the native
loop request's identifier preconditions.

The input record itself is the claim, written before any executor or scoped
publication callback. A matching completed result can be reused. A claim without
a result is uncertain, including operation exceptions, cancellation and result
write failure: never rerun it automatically. Storage/busy/recovery failures are
reported as nonretryable CLOUD_TOOL_RECOVERY_REQUIRED, not bad arguments or
verified external failure. A failed write that actually persisted a claim also
blocks replay. Successful output is saved before a late owner-change check so
its original observation is not lost.

All ordinary, recall, publication and milestone callbacks share this envelope.
Existing disclosure admission, native permissions, source restrictions, effect
claims, collaboration publication/receipt checks, research deadlines, batching
and observation recording remain responsible for their own policies. The
wrapper does not grant execution or make a successful receipt goal acceptance.

Current profile, readable/unlocked state, task cancellation and captured session
privacy/tracking/status/merge/roster flags are checked at invocation boundaries.
The persistence decision is fixed for the stream: private, tracking-paused or
legacy missing-session contexts use a request-local in-memory journal instead
of persisting their tool inputs. Changing flags aborts that stream's admission,
rather than silently moving its claims between stores.

Reused results explicitly say replayed, no new execution, no fresh observation.
They do not create new research or collaboration observation records. Cached
publication receipts cannot keep a new_execution=true/replayed=false claim.
Original collaboration observations remain in their history store; this wrapper
does not fabricate a fresh evidence receipt for a cached output.

Cached image annotations restore only the original SHA-256-named protected file,
after validating the index, digest, byte bound and content hash. The existing
image-card registration is shared by fresh rendering and restoration. Missing
or changed artifacts fail without rerendering the tool. Rendering, output hash,
directory/protection policy and normal image selection remain unchanged.

## Limits And Verification

This does not persist/replay provider response frames, resume a whole stream
after app restart, reconcile unknown external effects, add a liveness controller,
or deduplicate a deliberately new request/round/slot. A caller must not assign a
new identity to bypass an uncertain original invocation. Private/request-local
journals cannot provide cross-process recovery. There is no persisted privacy
mode marker for a later independent stream reusing that private request ID.

Boundary validation is not an atomic lock across an already-running batch or
actor hop. It does not replace full source/task authorization or reconcile
historical cross-profile inputs. In-flight work can finish and retain its owned
result. Existing journal storage growth and multi-process coordination limits
remain. Restoring source evidence/receipts and complete session UI state remain
separate from retaining an invocation's output.

Fifteen synthetic Swift fixture methods cover completed/encrypted replay, input
drift, uncertain outcomes, pre/post claim write failure, result write failure,
duplicate leases, separate owners/requests/rounds/slots, owner admission, late
owner change, artifact-restoration failure, publication replay metadata and an
invalid image record. They are authored, not compiled or executed.

Only JS/source contracts, iOS project structure and whitespace checks are used.
No Swift/native build, XCTest, device/simulator/live model/network test, full
repository check, CI inspection, IPA, private evidence upload or remote
approval/merge is performed. Runtime/storage/privacy/concurrency acceptance and
full Android parity remain unverified.
