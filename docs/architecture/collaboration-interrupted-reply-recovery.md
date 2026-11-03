# Interrupted collaboration reply recovery

## Ownership and commit ordering

A remote model completing its assignment does not complete the host-owned goal.
The Android coordinator must durably apply that member's result before scheduling
dependent members. Transport delivery, evidence acceptance, and goal acceptance
remain separate acknowledgments.

Managed connector dispatch now carries the original child run, supervisor run,
agent, and delivery mode to the transport boundary. The encrypted receive intent
is committed with the actual source/contact/conversation/turn/task identity before
publishing a Desktop request or starting a cloud request. The later dispatch
receipt may register the same identity again, but cannot erase a completed result
or regress an applied acknowledgment to pending. Conflicting reuse is rejected.

## Recovery of older interrupted runs

For an interrupted, user-authorized RUN, the coordinator compares each RUNNING
node with its receive ledger. If a dispatched node has no receive intent, it
reconstructs that intent from the original checkpoint and a single matching
persisted wire identity. It never selects a substitute model, retries the model
assignment, or replays tool side effects during this operation.

Existing authenticated status and paged-result recovery retrieves the original
remote execution. Pairing, route, execution generation, terminal delivery, and
supersession checks still apply. A transport receipt alone cannot satisfy an
interrupted journal node: an exact pending child may retrieve its original body
again until the supervisor has committed its result. Duplicate result application
remains idempotent.

An unregistered or ambiguous wire identity is not permission to redispatch.
Explicit PAUSE/STOP, cancelled parents, undispatched nodes, unrelated turns, and
finished runs do not enter this repair path. A successful model reply is still
subject to the existing evidence and publication checks; recovery cannot turn an
unverified research contribution into accepted evidence or a completed goal.

## Presentation

The group panel prefers unresolved research over newer follow-up turns. Once the
research is genuinely terminal and has no continuing/blocked goal, the newest
turn becomes current. Unresolved projections are not evicted by the finished-turn
history budget. This is a read-only projection and does not alter user control or
scheduler state.

## Regression coverage

- Dispatch/process-death gap and recovery from the original wire identity.
- Resume only queued successors, without invoking the completed member again.
- Fast reply before the later dispatch receipt, including encrypted store recreation.
- Duplicate results and conflicting owner registration.
- Foreign identities, explicit pause/stop, terminal teams, and undispatched nodes.
- Transport receipt versus missing supervisor result.
- Completed follow-ups cannot mask or evict interrupted research projections.

The fixture tests use isolated run identifiers and do not clear user history,
change pairing, or call a real provider. Live validation must separately observe
the affected run's original result being applied and its queued successors
becoming schedulable; it must not claim the underlying research goal has passed
acceptance merely because recovery succeeded.
