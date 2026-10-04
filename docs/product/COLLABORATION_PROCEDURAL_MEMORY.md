# Evidence-bound procedural memory

This is collaborative-evolution increment 3: accumulate reusable methods and failure experience from completed work. A durable summary alone is not an acquired capability. The method must be retrieved, bound to a new task, executed through the normal Agent runtime, and evaluated again.

## Two kinds of memory

- `procedure_skill` wraps an independently retained `capability_lesson`. It preserves the exact method, original scope, contraindications, transfer test, experiment and rollback references. Metadata supplies a name, retrieval keywords, input descriptions and limitations. It cannot replace the reviewed method with untested steps.
- `failure_experience` stores original failed tool observations, the member's interpretation and uncertainty, conditions where the failure matters, alternative remedies and a reconsideration condition. Host facts and proposed explanations remain separate. A transient network failure does not become a permanent prohibition.

Both are immutable, encrypted workspace records. Existing evolution directory paging and full workspace/evidence recall serve them to Android cloud, native and remote Desktop Agent paths. Group authorization and independent-round isolation still apply; future tasks in the same group may retrieve the original records. Private conversations and other groups are not implicitly exposed.

Failure classification distinguishes explicit failed/false-success outcomes from absent, false or empty error fields. Historical observations are not rewritten; a legacy record with an empty/false error cannot be promoted into a new failure experience solely because its old envelope says failed.

## Actual reuse

The coordinator can attach `procedure_use` to ordinary live or next-round DAG work. It names the exact skill revision and digest, supplies explicit inputs, explains applicability, and references relevant failure experiences. The host validates this before committing any sibling work in the batch.

The selected worker receives the exact retained method, new inputs, applicability/avoidance conditions, failure notes and rollback reference in its persistent goal-contract materials. This is cognitive procedural guidance for the existing Agent executor, not a new executor, `.gskill` installation, arbitrary script interpolation, or tool-permission bypass. Inputs and retrieved text remain task data. Existing tool authorization, cancellation, side-effect recovery and goal validation remain authoritative.

The stable work ID pins the binding. Restoring the same work cannot silently change its inputs or method. A new task may deliberately reuse the same skill under a new work ID; this is different from retrying an already completed side effect. Changed underlying evidence/target versions reject new admission until revalidated. Already admitted work keeps its original snapshot and recovery semantics.

Terminal outcomes retain actual status, elapsed time when known, output digest and the original binding before a round is replaced. Coordinators inspect these facts when deciding what to reuse, revise or test next. Runtime success is not a learning score or evidence of generalized improvement. Changes to the method require a new experiment and independent retention rather than inheriting the previous method's approval.

No fixed number of failures, research rounds or execution steps dictates the strategy. Ordinary work without a procedure binding performs no extra workspace reads. This increment introduces no new polling service and makes no UI changes.

## Design basis and boundaries

[Voyager](https://arxiv.org/abs/2305.16291) motivates preserving and retrieving successful methods rather than only conversational summaries. Its executable Minecraft skill library is not evidence that this implementation improves arbitrary research. [Reflexion](https://arxiv.org/abs/2303.11366) motivates retaining feedback between attempts without changing model weights. Here, interpretations remain tied to original observations and uncertainty.

The current procedure is model-applied task guidance. Deterministic package generation, sandbox execution and installation are separate tool-development capabilities, not claimed by this increment. Automatic semantic retrieval ranking, cross-domain transfer quality, independent real-model improvement, and long-duration deployment evaluation still need empirical validation. Synthetic fixtures establish publication, admission, scope, actual runtime context delivery and persistence only.
