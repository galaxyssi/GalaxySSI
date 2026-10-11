# Method Evaluation Recall

Execution completion is not evidence that a saved method is useful. A member selecting a
workflow can now inspect the existing, exact-version comparison record without browsing
the entire learning directory manually.

`capabilities` and ordinary `method_history` responses include `evaluation_recall` for
workflow methods. Invoke that selector, or use:

```json
{"mode":"method_history","view":"evaluations","object_id":"<id>","revision":1,"sha256":"<digest>"}
```

The phone links existing `experiment_plan`, `experiment_result` and `capability_lesson`
revisions through host-recorded `workflow_comparison` bindings. Both the baseline and
candidate can discover the same comparison, with their distinct variant identified.
Results include successful, incomplete, inconclusive and regressed measurements, and
retain/revise/reject reviews. Existing experiments and learning decisions are immutable:
a new experiment does not overwrite an earlier outcome. A result and its review are one
linked experiment, not independent votes.

The bounded on-demand scan uses the existing evolution index and immutable rows; there is no background worker,
new model call, copied evidence database or destructive migration. Continue `next_cursor`
even when a page has no matching records. The cursor binds the exact method and caller
scope. A concurrent publication requires a new scan to guarantee coverage; pages are not
a snapshot. Full records and original observations remain available through existing
workspace/evidence selectors. Excerpts do not count as a complete evidence read.

Android cloud, native-phone and Desktop remote adapters share the selector contract.
Desktop remains a task-bound bridge: the originating phone resolves visibility and
comparison links. Revoked access, hidden counterparts and cross-group references cannot
be bypassed by supplying a method name or copied digest.

Members use the returned conditions and contrary evidence to decide whether to reuse,
adapt, acquire a discriminating observation, or reject a method. The feature does not
automatically change an active workflow or promote a method. No matching comparison means
unknown evaluated history. Arithmetic on a saved tool report is not independent truth,
causality, generalization, or proof of capability growth. Ordinary unregistered manual
method use and comparisons that were never published are outside this directory's coverage.

Validation covers exact-version joins, negative outcomes, immutable historical records,
bounded pagination, access isolation, adapter schemas, cloud loop progress and encrypted
device reopen. Behavioral benefit still requires prospective real-model experiments;
passing these product tests does not establish a learning or multi-agent quality gain.
