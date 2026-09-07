# Evolution process termination evidence

Desktop 1.0.44 adds an OS-observed termination boundary to isolated Windows
evolution execution. This builds on task OS ownership and Windows Job Objects;
it is not an additional action budget or a chat execution policy.

## Launch and recovery order

1. Acquire the existing per-task OS ownership lock.
2. Verify any previous process ownership records for this task.
3. Create a random named, non-inherited Windows Job with kill-on-close enabled.
4. Persist and fsync the job identity before starting the command guardian.
5. Assign the guardian to the Job, then send its execution permission byte.
6. On restart, acquire task ownership before reading the same journal.
7. Query the Job's active process count. Only zero, or a definitive missing Job,
   permits retiring the record and continuing recovery.

The global Windows object namespace avoids confusing another login session's
missing local name with process termination. No PID-existence heuristic is used.
The query uses a short-lived non-inherited read handle and does not change Job
limits or explicitly terminate a different executor's Job.

Evidence contains only schema version and a random Job name, not commands,
prompts, credentials, or repository contents. Task directories use hashed IDs.
Nested Agent scopes inherit the task journal. Ordinary chat remains outside the
owned execution scope. Candidate commands, GitHub CLI commands, publication,
manual discard, and restart cleanup use the scope when owned by a task.

## Deferred recovery

An active Job, malformed record, or failed OS observation leaves task status and
worktree intact. The task records `process_termination_pending`; the scheduler
rechecks these interrupted records when evolution and automatic task starting
are enabled. It does not convert an observation error into a confirmed exit.
Manual start, synchronous start, publication, and discard perform the same check
after acquiring task ownership, releasing that ownership if the check fails.

Normal close attempts to retire its own record only after an OS query reports
zero. Remaining records are retried during recovery; handle closure by itself is
not treated as sufficient evidence. Records from a partially written launch are
conservative recovery failures, never permission to remove a worktree.

## Validation

- Real Windows Job accounting while a guarded process is alive and after exit.
- Real host `os._exit(23)`, followed by a new manager reading durable evidence.
- Real Git worktree stays present while an orphaned owned process is active;
  after termination, recovery removes the worktree and its candidate branch.
- Journal persistence failure prevents the target command from running.
- The target observes its durable record before executing application code.
- Active, unavailable, and malformed evidence cannot authorize cleanup.
- Enabled scheduler retries deferred recovery; disabled evolution does not.
- Normal chat process behavior, stdin, output, and exit codes remain covered.

## Remaining scope

This does not retroactively attest processes launched by older versions without
journals. It does not establish ownership for POSIX descendants, independently
started services/WMI processes, or shared persistent CLI pools. It also does not
prove external tool effects execute exactly once, or replace the remaining
real-provider, device-reboot, and end-to-end long-running campaign acceptance.
An operator deleting state or corrupting a journal is outside normal recovery;
unknown persisted evidence is retained for diagnosis.

## References

- [Windows Job Objects](https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects)
- [OpenJobObjectW](https://learn.microsoft.com/en-us/windows/win32/api/jobapi2/nf-jobapi2-openjobobjectw)
- [Job accounting information](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-jobobject_basic_accounting_information)
