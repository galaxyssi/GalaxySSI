# Collaboration source availability

`collaboration_recall` (cloud or Desktop) and the task-bound Android native
recall tool accept `mode=source_access`, exact workspace `object_id`, `revision`,
`sha256`, and optional `cursor`. The current host assignment supplies identity.

The response lists only the saved root's direct `parents` and
`host_observations`. It does not follow links inside member-authored bodies,
recursively traverse the graph, or search unrelated tasks. Each row preserves
the exact reference and its field/index in the original:

- `available`: that exact source is currently readable; `read_original` gives
  the normal recall selector. This is not evidence of reading or verification.
- `missing_changed_or_out_of_scope`: the source cannot currently be read. This
  deliberately does not reveal whether an inaccessible original exists or
  expose its contents or author.

No access is granted, task dependency changed, model started, or read-coverage
receipt issued. Existing exact grants and peer/coordinator sharing still apply.
An Agent can use the result to request missing inputs through existing
coordination or report an evidence gap; the host does not automatically decide
which source is relevant or sufficient, nor weaken independent review.

Pages contain at most 20 reference checks, not a limit on source count. Cursors
bind the exact root and assignment, including dependencies and grants. A scope
change requires restarting without a cursor. The immutable reference list is
stable; availability is checked afresh on each request and is not a snapshot.
This is a metadata inspection, not a new research stage required for every task.

## Verification

- JVM: direct-source scope, reference identity, non-disclosure, pagination and
  bounded lookups, stale/cross-scope cursors, explicit grant behavior, unchanged
  persisted publications, and revoked access.
- Android: both cloud and native entry points, exact dispatch binding, durable
  reopen, unavailable originals, explicit grants, and no read-coverage change.
- Desktop: strict selectors, authenticated forwarding, no confirm phase or
  model invocation, and no caller-supplied identity.

These checks validate the feedback contract. They do not establish that a model
will choose better evidence, repair a missing dependency, finish sooner, learn a
new capability, or outperform a single Agent. Those require separate real-model
observations and controlled comparisons.
