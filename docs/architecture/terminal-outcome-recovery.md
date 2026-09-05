# Terminal outcome recovery

Desktop 1.0.10 extends the encrypted final-reply archive to failed, timed-out and
cancelled executions. This is the Desktop persistence/observation phase, not a
claim that Android terminal-result consumption or paired-device acceptance is
complete. This phase contains no Android changes; the installed S20U test build
remains 1.0.15. iOS is out of scope.

## Committed facts, not inferred outcomes

The normal terminal-event path archives the actual error and any existing result.
The archive stores a typed terminal reason when there is no text, including a
normal cancellation. It does not invent an explanation, relabel failure as
success, invoke a provider, or scan the task workspace for artifacts. Non-success
result callbacks use the same payload builder and skip artifact finalization.
Cancellation events with existing partial/result text are no longer suppressed
on the assumption that a result callback will follow.

The task/Run transaction remains canonical. If the process dies after committing
the task but before its archive callback, a fully scoped page request can rebuild
the error outcome from committed task data. Archive failures do not suppress the
existing task event. A later request retries the missing projection. Successful
replies are not rebuilt from task text because that would change their original
artifact/rendering payload.

Recovery metadata reads use a committed, projected task snapshot. They do not
populate the live task cache or hydrate large output chunks. Body hydration is
requested separately, only for a matching failed/timed-out/cancelled execution.
Identity and generation are checked again after that read to reject a retry that
raced the metadata lookup. The seven existing route/conversation/task/turn/
contact/source/agent identity fields are required.

## Execution generations

`execution_generation` is a positive JSON integer. It is returned by status
observations and page responses and included in new final-result envelopes.
Pages and acknowledgements accept the same field. Generation one uses the
existing archive key, including for pre-generation records. Later generations
have independent encrypted bodies, hashes, page authentication and receipts.
An acknowledgement for one execution cannot delete another execution's reply.
New executions also have distinct deterministic transport message IDs.

Old clients that omit the generation address generation one only. They cannot
silently read or acknowledge a later execution. The Android follow-up must retain
the fresh observed generation, pin every page/receipt to it, and reject responses
older than a newer known execution. The archive itself can deliberately retrieve
an explicitly addressed older generation; it does not claim that generation is
the currently running execution.

## Remaining work

- Android must consume typed terminal replies, persist their generation/status,
  stop waiting on cancellation, and pass actual failures into its existing
  recovery/failover loop. Failed replies must not inherit `success=true`.
- Persist partially downloaded result-page checkpoints and retain their exact
  execution identity across process restarts.
- Integrate terminal, transport, Run and transcript commits. The archive remains
  a recoverable projection in a different SQLite database, not one cross-store
  atomic transaction.
- The existing task-result outbox is task-keyed; generation-aware compare/delete
  and stale queued delivery handling still require a separate transport change.
- Perform paired Desktop/App network and process-death acceptance. Backend
  subprocess tests do not prove phone UI behavior or a five-second recovery SLO.

The default physical test device is S20U. Approximately twenty-second chat
responses remain acceptable for the current performance phase; no stricter
end-to-end latency claim is made here.
