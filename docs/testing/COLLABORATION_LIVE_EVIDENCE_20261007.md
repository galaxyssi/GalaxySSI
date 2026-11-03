# Live collaboration evidence

## Failure addressed

Desktop already records completed operational tool outputs while a Codex task is
running. Android previously created an import intent only after a terminal reply.
Consequently, an in-flight member could execute a measurement but could not obtain
its host evidence reference for an interim publication. More members or repeated
prose submissions cannot repair that missing information flow.

## Contract

- The first page of an authenticated, currently assigned `evidence` or `problems`
  recall refreshes that assignment's Desktop observations before reading the local
  ledger. Exact evidence pages, confirmations, subsequent browse pages and other
  recall modes do not trigger additional imports.
- Host task identity, execution generation, pairing, current membership and durable
  user control remain authoritative. Model arguments cannot select another task.
- Live snapshots stop at a caught-up index boundary. `snapshot_imported` is not a
  terminal archive. `host_evidence_sync` reports the imported cursor, skipped large
  originals, archive seal and restricted coverage; it never claims full provider
  history or semantic verification.
- New first-page reads resume from the saved cursor. Ordinary chat creates no jobs
  and caught-up snapshots do not poll in the background.
- Terminal notification upgrades the same durable job. An import already in flight
  cannot overwrite that demand. A terminal job waits for a sealed archive, yielding
  between recovery passes rather than spinning or repeating tool execution.
- Concurrent recovery and live reads share a per-job gate. A stalled task does not
  hold a global import lock over another task's live read. Cancelled waiters release
  their gate references.
- Hash-checked original pages survive partial transfer and process death. Ledger
  recording precedes cursor advancement and remains idempotent after a crash.
- A live RPC spends at most ten seconds importing, with reply time reserved from
  its actual expiry. This is an RPC responsiveness boundary, not a limit on research
  duration, steps, evidence count or background continuation. Remaining transfer is
  explicitly pending and durable.

## Verification

Automated coverage includes incremental live tails, terminal arrival during page
transfer, empty unsealed archives, concurrent cursor ownership, cancelled waiters,
quarantine/revocation, original hashes and assignment isolation. Device coverage
uses real encrypted stores to publish a live observation and read it as an assigned
peer before any terminal notification, then resumes the terminal archive.

Android 1.4.89 (1174) compiled with 1,350 focused collaboration/runtime unit tests
passing. On S26U, three targeted encrypted-store tests passed, followed by a
two-process checkpoint test (seed PID 26088; recovery PID 26130). The APK SHA-256 is
`8b05816df920228638273d24ea40146c67da438771301020dd2c565780effd9b`.

One separately bounded real-model handoff used three members, an eight-minute
deadline and at most six phone dispatches. All six captured model contexts used
the App-selected `gpt-6-astra` with `high` reasoning. The author obtained a live,
unsealed snapshot, read the original command observation and published an interim
artifact before finishing its assignment. An assigned reviewer read that exact
original and published a review without rerunning the calculation. The frozen
observable record contains one unique successful calculation command; this is not
a claim that all provider activity is visible.

The overall trial **failed** its predeclared deadline. The reviewer supported the
arithmetic result but left full handoff and scope acceptance unverified: its
workspace view did not expose the author's separately confirmed original read,
and final goal-coverage work was incomplete. Operator-side receipts confirm the
read, but those receipts must not be substituted for what the peer actually saw.
Four of six Desktop tasks completed and two were cancelled at the boundary;
cleanup was confirmed. Repeated coordination and coverage work remain unresolved.

This is an engineering acceptance exercise, not evidence of scientific innovation,
retained learning, transfer or superiority over a single Agent. Raw research
protocols, private model output and the paper are kept outside Git.
