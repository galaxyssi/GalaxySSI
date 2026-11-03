# Collaboration Peer Request Delivery

## Failure Modes

Directed research questions previously selected only the first three requests
and first three recipients, truncated questions at 1,200 characters and candidate
IDs at 80 characters, and used question-only identity. The recipient's task
context omitted candidate metadata. Long finalized artifacts could also lose
all request fields in compact handoffs before runtime routing.

These are transport and context defects, not evidence that a model chose not to
collaborate. They can suppress a requested challenge or make its target ambiguous.

## Contract

- Route each valid directed request to all its distinct in-group recipients.
- Preserve complete questions and candidate IDs within the existing message
  envelope. Reject malformed or oversized fields with field-specific publication
  feedback; larger evidence belongs in retrievable workspace originals.
- Keep ordinary legacy message IDs stable. Distinguish different candidate
  reviews that use the same question, while deduplicating exact replay.
- Persist requests from the full archived output before compacting the handoff.
  Recovered late replies use the same finalizer. Interrupted routing can replay
  without duplicating messages already durably enqueued.
- Include candidate/stage metadata in the receiving member's evidence context.
  Messages remain untrusted evidence, not permission or an execution command.
- Use a process-shared critical section for encrypted mailbox read/modify/write
  across finalizer/runtime instances, and save each routed batch once rather
  than rewriting the full mailbox separately for every recipient.

This does not wake every member, bypass independent-exploration isolation, create
a second execution loop or deliver messages in the middle of a running model
call. Members consume pending messages at the existing eligible checkpoints.
The subsequent [mailbox retention change](COLLABORATION_MAILBOX_RETENTION.md)
replaces the legacy 5,000-record snapshot with indexed encrypted rows. Unlimited
storage capacity and sustained large-fanout model performance are not claimed.

## Validation

Unit regressions cover seven questions to eight peers, full long-question and
candidate preservation across mailbox encode/reload, identical-prefix questions,
candidate-specific deduplication, excluded self/outsider recipients, and precise
oversize/type feedback. Finalizer tests cover interruption after enqueue,
compaction without request fields, replay and unchanged workspace version count.
The runtime context test checks that candidate metadata actually reaches a worker.
An additional device fixture covers concurrent batches through independent
encrypted mailbox instances. It must be run on an authorized phone; compilation
alone is not a device-test pass or proof of cross-process concurrency.

These are delivery tests, not evidence that a real peer contributes a useful
correction. A capability study must still track the contributed counterexample,
subsequent executable revision, independent outcome and fresh-task transfer.
