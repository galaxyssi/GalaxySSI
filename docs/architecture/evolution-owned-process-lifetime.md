# Evolution owned process lifetime

Desktop 1.0.43 adds opt-in Windows process-tree ownership for isolated evolution
execution. It uses the documented
[Windows Job Object mechanism](https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects)
with `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`. It does not add CPU, memory, priority,
or execution-time limits.

## Launch ordering

The host creates a non-inherited job handle and starts a small standard-library
guardian with the base Python interpreter. Using the base interpreter avoids a
virtual-environment launcher creating another process before job assignment.
The guardian uses isolated startup and launches no command until it reads the
host's one-byte go signal.

The host first assigns the guardian to the job, then sends the go signal. Its
ordinary child processes inherit job membership. If the host disappears before
assignment, stdin EOF makes the guardian exit without launching the command. If
the host disappears afterward, closing its last job handle terminates the owned
tree. Assignment failure does not fall back to an unowned launch.

On normal command completion an exit watcher closes the job, so descendants
retaining inherited stdout cannot leave the host waiting forever for EOF.
Explicit termination and exceptional cleanup also close the owned job.

## Integration and scope

Evolution background and synchronous task bodies enter an owned-process context.
Their command runner and the isolated CLI Agent launch path use the wrapper.
Direct evolution Agent calls also enter this context. The context is thread-local
and restored on exit, including exceptions.

Normal chat launches and persistent shared CLI transports retain their existing
launch behavior. POSIX execution is unchanged in this stage. No existing process
is retroactively attached to a job, and no running Desktop or phone is redeployed.

The wrapper supports the stdin modes used by these paths: PIPE, DEVNULL, or none.
It preserves binary/text output, Unicode and binary stdin, stderr, and exit status.

## Evidence and remaining acceptance

Real Windows tests cover a crashing host with a guardian, child and grandchild;
all process handles signal termination. Other cases cover EOF before assignment,
assignment failure, explicit kill, inherited stdout, and byte-exact pipe behavior.
Ten local startup samples per mode measured median simple-Python launch times of
31.69 ms normally and 93.85 ms through ownership. These are local microbenchmarks,
not end-to-end or P95 chat latency claims.

Windows Job Objects do not cover processes created through independent services
such as WMI, remote services, or already-shared process pools. Cross-platform
orphan handling, durable observation of the final process-termination boundary
before worktree recovery, and real-provider/device-reboot acceptance remain
required. This lifetime mechanism does not undo external side effects or establish
exactly-once execution.
