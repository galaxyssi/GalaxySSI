# Local Inference Cancellation Propagation

Independent iOS execution-lifetime follow-up to the ongoing Android #3007
comparison, based on main `c6bad3465c673dfb2dcecb23b095185c129c7447`.
It complements #4705's model-loop signal bridge; this PR does not duplicate
that loop change or claim full Android parity.

## Production Changes

LocalModelInferenceRuntime previously accepted an explicit token but did not
connect cancellation of its Swift caller Task to its serial DispatchQueue.
The asynchronous entry now owns an existing lock-protected source and installs
a Swift task cancellation handler. Worker admission and result delivery check
the OR of that source and the caller's explicit token. A cancellation observed
with a backend error is returned as CancellationError, not ordinary model failure.
Noncancelled failures retain their original path and continuation still resumes
exactly once through the existing worker operation.

LocalModelCooperativeRuntime now accepts a defaulted explicit token and passes
it to both advisory planning and answer generation. Check Swift task and token
cancellation before readiness work, after advisory planning, before every answer
candidate, after generation, and before retaining a candidate error for fallback.
Thus the existing optional planner try? cannot swallow a cancellation and start
the answer model. Existing fallback for ordinary noncancelled errors is unchanged.

The local Web tool adapter passes the same combined request/inference token
on its cooperative branch as its existing exact-profile branch. Profile ranking,
selected-model constraints, thinking mode, prompt text, resource arbitration,
native backend interfaces and model installation rules are unchanged.

## Limits And Verification

The unchanged native backend API cannot interrupt one in-progress synchronous
model load or token-generation call. Queued cancellation prevents worker admission
when observed, and cancellation after work begins rejects its eventual result;
it does not force immediate queue release, cancel the underlying C++ computation,
or retract work already started. Admission/result races are not a new atomic
transaction. Five new Swift fixture methods cover pre-cancelled explicit-token
and Swift-task admission for direct/cooperative entry points plus unchanged
ordinary unavailable-backend failure. They use an unavailable backend and are
NOT compiled or executed. Mid-generation, between-candidate, real queue ordering,
device resource use and native cancellation acceptance remain unverified.

The source guard retains exact production/fixture deltas and existing ownership
hooks, freezes backend/token interfaces and rejects fourteen synthetic source
mutations, including a relocated check with the correct overall count. Full
reviewed source comparisons pin the actual stage locations before inversion.
No Swift build, XCTest, live model/network/device, CI monitoring or IPA
is included. Backend interruption and broader parity remain unfinished.
