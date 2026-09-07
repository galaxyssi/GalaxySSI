# Evolution task OS ownership

Desktop 1.0.41 extends the local-manager guards introduced in 1.0.40 with
nonblocking, OS-held per-task ownership. All upgraded executors accessing the same
evolution state directory use the same task lock identity.

## Protected operations

Execution claims ownership before changing task status or starting its worker.
The admitting thread transfers the held handle to the background worker; that
worker releases it only after returning from execution. Synchronous execution
holds the same lock through its complete call. Failed thread startup releases it.

Publication, rollback, restart recovery, and cancellation also participate:

- An executor cannot restart, publish, or delete the worktree of a task owned by
  another executor.
- Recovery holds ownership through cleanup and the fresh status write, not just
  while checking whether a previous owner is alive.
- Cancellation from the owning manager still signals its worker. A different
  executor does not falsely mark that running task cancelled: it reports
  `task_owned_elsewhere` because it cannot signal the other manager's worker.
- Independent task IDs can execute concurrently. This change is not a global
  capacity controller and does not serialize unrelated tasks.

## Lock behavior

Task IDs map to SHA-256 filenames inside `task-owners`. Windows uses a nonblocking
byte-range lock; POSIX uses `flock`. CI observer locks now share this implementation
while retaining their existing owner identities and missing-owner behavior.

Lock files are never unlinked after release, preventing inode replacement races.
An expired timestamp or reused PID cannot steal a live lock. The OS releases the
handle on process exit. Failure to open or verify a lock is not permission to
execute or roll back a task.

## Evidence and remaining boundaries

Tests exercise two independent managers over one state directory, live background
and synchronous execution, publication failure, failed thread startup, unavailable
locks, and ownership throughout cleanup and status persistence. A real subprocess
runs through `EvolutionManager.run_sync`, holds ownership, and exits with
`os._exit(23)`. The parent confirms it cannot take over while the child is alive,
then restores the interrupted record after exit without a lease timeout.

The crash fixture stops before launching an external coding CLI. Surviving child
processes, commands that already changed an external service, and uncertain GitHub
publication outcomes still require durable side-effect reconciliation. OS task
ownership alone is not exactly-once execution. It also does not protect an old
executor that ignores these locks, another machine using a different state store,
or a filesystem that does not provide reliable local locking semantics.

No existing Desktop process or Android installation is replaced by these source
changes. Device-reboot and long-running real-provider acceptance remain required.
