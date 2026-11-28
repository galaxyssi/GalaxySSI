# Local And Native Inference Cancellation

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
The optional planner now catches ordinary errors separately and rethrows
CancellationError unconditionally instead of using try?. Answer-candidate
catches also preserve cancellation even if a custom token later changes back.
Existing fallback for ordinary noncancelled errors is unchanged. The direct local
planning provider retains CancellationError rather than turning it into an
ordinary model-unavailable error.

The local Web tool adapter passes the same combined request/inference token
on its cooperative branch as its existing exact-profile branch. Profile ranking,
selected-model constraints, thinking mode, prompt text, resource arbitration and
model installation rules are unchanged.

## Native Generation Follow-up

The backend protocol gains a cancellation-aware generate requirement with a
default adapter around the existing method. Legacy implementations remain source
compatible; native implementations can override it through the protocol witness.
The runtime passes the combined token through preflight/load boundaries and to
that overload, preserving CancellationError from the backend.

The llama backend uses a new synchronous C cancellation callback. A retained-for-
the-call Swift context polls the token and latches any observed cancellation.
Neither callback nor context escapes the native call; the C callback cannot
reenter runtime functions while the generation mutex is held. The existing
four-argument C export delegates with no callback and remains available.

Native code polls before/after each prompt decode batch, before each sampled
token, after each generated-token decode and before publishing the final string.
An observed cancellation frees the sampler, clears current KV memory and returns
null, not a partial assistant response. Swift releases any nonnull response
buffer and returns CancellationError on a latched/late cancellation. No weights,
backend configuration, build flags or embedding encoder behavior changes.

## Limits And Verification

Cancellation does not interrupt one in-progress llama_decode, prompt formatting/
tokenization or synchronous GGUF model-load operation. It stops native generation
at the next polled boundary, not at a guaranteed time. Ordinary legacy backends
without a cancellation-aware implementation still check only around their call.
Queued work is not removed immediately, admission/result races are not a new
atomic transaction, and bytes/effects already sent cannot be retracted.

Eleven Swift fixture methods are authored but NOT compiled or executed. Five
cover pre-cancelled explicit-token/Swift-task admission for direct/cooperative
entry points and ordinary unavailable-backend failure. Six use synthetic legacy
or cancellation-aware backends to cover pre-dispatch refusal, rejected partial
result, normal success/error, CancellationError retention and protocol witness
dispatch. They do not load a model. The C ABI, ARC callback lifetime, mid-decode
polling/cleanup, real queue ordering, latency and device/native cancellation
acceptance remain unverified.

The source guard retains exact production/fixture deltas and existing ownership
hooks, retains old backend/C entry compatibility and rejects thirty-four synthetic
source mutations, including a relocated check with the correct overall count. Full
reviewed source comparisons pin the actual stage locations before inversion.
No Swift build, XCTest, live model/network/device, CI monitoring or IPA
is included. Interrupting an active decode/load operation and broader parity
remain unfinished.
