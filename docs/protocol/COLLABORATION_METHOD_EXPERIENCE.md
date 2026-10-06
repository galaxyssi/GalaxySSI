# Method execution experience

Method discovery alone does not tell the next task how a method behaved before. The host now retains terminal observations for admitted `workflow_method` and `procedure_skill` bindings in the existing group workspace database.

## Recording

The execution store records method-bound terminal results before committing the corresponding lifecycle event. Replaying that event is idempotent. A later recovered result is an additional observation, not another claimed attempt. Unrelated progress and ordinary tasks do not open the workspace. Group deletion removes the observations and their indexes with other group workspace data.

An observation preserves the exact method revision and digest, host binding and inputs, goal and assignment, member and work identity, selected model, actual execution status, error, timestamps, output digest and available delivery receipt. Unknown quality effects and causal contribution remain null. A successful dispatch with rejected delivery remains distinguishable from successful delivery. Full output remains in the original archive when its delivery receipt supplies an archive reference.

This is observational history, not a measured success rate, independent trial count, proof of comprehension, actual served-model attestation or automatic method adoption. Old runs are not retroactively classified or backfilled as if this feature had observed them.

## Recall

Capability search supplies `usage_recall` for supported methods. All cloud, native and Desktop recall paths use the same phone-owned scope:

```json
{"mode":"method_history","object_id":"<exact method ID>","revision":1,"sha256":"<exact method hash>","cursor":""}
```

The response contains a bounded directory and `next_cursor`. Follow cursors even after an empty visibility-filtered page. Read one original with:

```json
{"mode":"method_history","record_id":"<returned record ID>","offset":0}
```

Follow `next_offset` for full conditions and errors. No current-round peer observations are exposed without the existing dependency relationship. Future turns in the same authorized group can inspect history; other groups and revoked members cannot. Cursors bind the method and assignment. Exact historical method versions remain separately queryable; a revised method does not silently inherit another version's outcomes.

The Agent can use these facts to diagnose a failure, check applicability, choose another method or propose an experiment. Runtime state does not decide that a faster or successful dispatch proves scientific effectiveness. Existing independent validation, transfer and retention requirements remain unchanged.

Managed cloud progress recognizes newly read characters from executed, pinned history pages and newly discovered history records. Repeated pages, changed originals, failed calls and model-authored claims of tool output do not reset stagnation. Reading progress does not increase scientific quality or acceptance scores.
