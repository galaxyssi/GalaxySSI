# Scoped Collaboration Execution Locations

The execution store is a host dependency. A model cannot choose a database,
change a run owner, or use a location record to start work.

## Contract

Context-backed `EncryptedAgentTeamExecutionStore` instances register the exact
run, conversation, turn, task, team and local storage namespace before creating
the execution record. Repeated creation by the same owner is idempotent; a
different owner or namespace is rejected. A pre-existing unindexed default
record also prevents an isolated store from shadowing it.

`CollaborationCoordinatorUpdates` resolves the authenticated source binding to
this registered location. It still checks the original source binding, current
incremental-coordinator assignment, completion status, pause/stop state and
exact milestone grants. Cloud, native and remote recall use this same route.
The result is a read-only checkpoint/snapshot, not an executable controller.

The location registry does not merge isolated executions into default-store
enumeration. Normal background recovery therefore does not discover and launch
a second controller for an execution owned by another host runtime. Reopening
the store or process preserves the location; it does not itself resume work.

## Failure And Cleanup

- An absent binding retains default-store lookup for existing runs.
- A malformed, undecryptable, mismatched or missing mapped record fails closed.
  It must not silently use a same-named run in the default store.
- Removal, pruning and clearing verify namespace ownership and remove their
  own location records. They do not clear another store or its run bindings.
- The registration and execution row are in separate encrypted stores. A crash
  after registration but before the execution row leaves an unavailable owned
  location. The same owner can retry creation; another owner cannot claim it.
- Member authorization and result provenance remain separate from storage
  location. A valid location is not a grant to read another member's evidence.

## Validation Scope

Regression coverage includes normal and isolated live coordinator updates,
native/cloud recall, exact evidence confirmation, late revisions, independent
member isolation, pause/resume, owner conflicts, failed mapped reads, scoped
cleanup and process reopening. A separate seed/recover device phase checks a
real process restart without model calls.

This fixes execution-context consistency. It does not prove useful hypothesis
generation, scientific discovery, task completion, collaboration advantage or
full network/Doze recovery. Those require their own real-task evidence.
