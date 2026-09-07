# Local implementation tool observations

Private local implementation uses a model/action/observation loop. A rejected
file action is an observation for the next model turn, not a successful edit and
not a reason for the host to invent a replacement edit.

## Failure classification

File tools report stable `error_code` values. In particular, write diagnostics
distinguish `read_digest_required`, `invalid_read_digest`,
`source_digest_mismatch`, and `write_scope_mismatch`. A complete uppercase SHA-256
is normalized before comparison; stale or fabricated digests are still rejected.
Path, encoding, missing-file, access, and storage errors are classified separately.
Malformed model JSON is identified as a model-action parsing failure, not as
invalid source code.

The model receives the diagnostic detail and decides how to recover. The host
never guesses a hash, bypasses the write scope, or changes the candidate itself.
OS error messages are replaced with static descriptions to avoid echoing private
paths. An OS failure has `effect: unknown` because an I/O error may occur after a
write was applied. The model must observe the file again rather than assume a
retry is safe. Rejected validation has `effect: not_applied`.

## Durable and visible projection

Each `local_tool_observed` audit event includes task identity, attempt number,
`tool_step`, operation, stage, success, error code, and effect. Step numbers are
local to an implementation invocation, not a global action budget. No source
body, filename, hash, model reply, or private reasoning is included in this
projection. Full file observations remain in the local model's bounded context.

The audit append is flushed before the Desktop event callback. A callback error
does not discard the observation or make an already applied file action appear
to have failed. It records `local_tool_delivery_failed` with the exception type
only. Audit storage failure propagates; the host does not report an unrecorded
observation as delivered.

This uses the existing evolution audit ledger. It does not claim atomic
file-action/journal commits, cross-process audit serialization, or exactly-once
external side effects. A crash between a file write and its audit append still
requires workspace reconciliation. Finish summaries remain subject to independent
host validation and do not prove successful publication or campaign completion.

## Verification

`test_local_tool_observations.py` exercises distinct write failures, unchanged
files after rejection, uppercase versus stale digests, private-data exclusion,
real file I/O, model observation/recovery, audit reopen, callback failure, and
audit storage failure. The opt-in real campaign harness includes the same typed
metadata in `task-events.jsonl` without persisting file observations.
