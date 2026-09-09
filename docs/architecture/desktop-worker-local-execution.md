# Worker Local Execution

Desktop 1.1.30 adds a callable Windows execution adapter for authenticated worker
grants. It is not automatically started by pairing, MQTT traffic or Desktop
startup. The normal App route is not automatically offloaded. Desktop 1.1.31
adds an explicitly activated [worker controller](desktop-worker-controller.md)
connecting the paired RPC client, this adapter, renewals and report delivery.

## Ownership Before Execution

`WorkerLeaseGuard` consumes a successful poll `WorkerRpcResult`. The local deadline
is the monotonic send time plus the smaller of 30 seconds and the coordinator's
remaining lease duration, minus a 500 ms safety margin. Receive time never resets
the TTL. The attempt-correlated RPC client prevents an old reply from being
combined with a new send timestamp.

Renewal requires the exact App/conversation/turn/task/generation, lease epoch and
token, a nondecreasing expiry, and a fresh send/receive observation. An unchanged
server clock observation cannot extend the budget. A regressing server clock,
expired guard or explicit cancellation fences the execution. Expired guards
cannot be revived. Only the authenticated controller may supply observations;
these Python objects are not standalone authentication credentials.

`WorkerExecutionJournal` uses the existing SQLite ledger transaction helper.
Its local execution identity hashes the coordinator's pairing/grant binding,
complete execution key and lease epoch. Provider, prompt, options and capability
token are bound by a separate immutable request digest. Renewal expiry changes
do not create a new job. A changed prompt or token under the same identity is
rejected.

The journal records `admitted -> dispatched -> reporting -> confirmed`. A CAS
transition must commit before any child starts. Replayed submissions and concurrent
callers cannot repeat the external dispatch. Terminal report content is committed
before the coordinator receipt, so receipt retries reuse the result rather than
running the model again. Reports currently use a single terminal sequence, 1.
Receipt confirmation is a trusted local operation after the RPC layer validates
the coordinator response.

A separate logical-task index excludes generation/lease epoch. A newly admitted
generation fences older queued generations, and a new version cannot dispatch
while another version of the same logical task is dispatched or uncertain. This
prevents local overlap during recovery; an uncertainty marker requires explicit
reconciliation rather than an automatic retry. Unrelated App/conversation/turn
identities do not share that gate.

Previously dispatched work is never automatically restarted. After ownership
loss, uncertain termination, invalid child output or a local execution failure,
the record remains fenced/uncertain for reconciliation. A different process owner
cannot claim the same grant, even if it was merely admitted. Confirmed records and
tombstones are not silently evicted: at 10,000 records, admission stops. Safe
compaction and explicit coordinator/worker recovery remain future work.

## Bounded Processes

`WorkerProcessExecutor.submit(...)` uses the existing App/conversation round-robin
`AgentWorkPool`. The App lane also includes the coordinator binding. Defaults:

| Resource | Bound |
| --- | --- |
| Active owned child trees | 10; configurable within the pool's 1..128 range |
| Local waiting jobs | Same as the configured worker count |
| Accounted active/waiting request JSON | 8 MiB per executor |
| Central coordinator waiting queue | Existing 10,000-record limit |
| Local identity/receipt journal | 10,000 retained records |
| Child terminal report read | 16 KiB, then existing report field limits |

The controller must advertise actual available capacity instead of pulling the
whole coordinator queue into a worker. These are request/count bounds, not exact
process RSS limits or evidence of 10,000 simultaneous model calls.

Each active grant runs in a separate owned Windows process tree. The existing
guardian assigns the child to a Windows Job before allowing it to execute and
records the Job identity for recovery. The parent checks its guard at startup and
at most 100 ms between process waits, also enforcing an explicit elapsed-time
budget. Cancellation/expiry closes only that owned tree. Quiescence is checked by
the recorded Job identity, not by an old PID or a presumed timeout. OS scheduling
is not a hard real-time guarantee; remote side-effect fencing remains required
for stronger distributed guarantees.

Non-Windows execution is explicitly unsupported until equivalent process-tree
ownership and recovery are implemented. No global process termination is used.
Closing an executor invalidates its active guards and cancels its own queued work;
it does not close the ordinary Desktop model server.

## Model And Images

The first adapter supports only locally installed Codex through the existing
`CodexAppServer`. Every grant gets a private working directory and conversation
thread mapping under its hashed execution identity. It does not load the normal
Desktop conversation map. Codex credentials stay in the worker's existing local
configuration; lease capabilities are not included in the child request file.
The coordinator must compile the intended conversation history into the dispatched
prompt. This adapter does not reconstruct missing conversation context by reading
other local sessions.

Default execution is read-only. A local operator can explicitly choose
workspace-write; incoming options cannot select a broader sandbox. Plan-only
requests always select read-only. Requested reasoning effort, response language
and execution budgets are passed through existing policy helpers. Disallowed
cloud/paid use and restricted network profiles are rejected rather than relaxed.
Sandbox policy is not a VM or a complete hostile-tenant isolation boundary.

Input images require inline base64 bytes and a matching SHA-256. Up to 12 images
are checked for a supported image format and at most 16 million pixels each.
Files use locally assigned names; remote paths are ignored. Image bytes are not
compressed or redrawn. They are passed as native `image_paths` to the model,
not replaced by OCR or a textual filename. Missing bytes, corrupt images and
unsupported attachment types fail explicitly.

Only PNG has been exercised with the real model so far. Blob-based retrieval,
non-image inputs, output artifacts, long/chunked output and other providers remain
unimplemented. Tasks requiring returned artifacts are rejected until that return
path exists. Intermediate files currently remain in the configured worker root;
retention/quota cleanup must be added before unattended deployment.

## Verification Boundary

Local tests cover monotonic expiry/renewal, stale generation/token/epoch,
out-of-order observations, immutable job reuse, restart ambiguity, concurrent
dispatch CAS, report/receipt idempotency, byte-preserving image materialization,
policy restrictions and queue/request-byte bounds. Windows process tests launch
real private fixture children, verify duplicate submissions do not relaunch,
reject a valid-looking report from a failed process, and cancel a tree with an
actual descendant using its owned Job identity.

The opt-in real Codex test uses a temporary in-process coordinator ledger and
two owned execution children in different turns of the same fixture conversation:
one text request with a unique marker, and one PNG
equation request with another marker. It maintains actual coordinator leases,
observes two active execution slots, validates both model replies and the complete
equation, applies terminal reports, and checks the original five-part identity
and source message ID. No real contact is enrolled. This proves real model/native
image execution through the new local adapter, not MQTT transport or physical
multi-host/phone acceptance.

Remaining end-to-end work after 1.1.31: normal-App admission/routing,
original-App artifact/result delivery over real MQTT, process-loss
reconciliation, and physical multi-host testing. The ordinary
S20U text/image results in the protocol document remain separate historical
evidence. This version is not a replacement for that acceptance test.

### Verification Record, 2026-09-09

- Final expanded task/worker/MQTT/owned-process regression: 586 passed, 296
  subtests, 1 opt-in live test skipped, in 97.22 seconds.
- The skipped live case was explicitly run separately on the final code and
  passed in 11.38 seconds. It performed two real Codex requests concurrently,
  including native PNG recognition, with local coordinator renewals and report
  confirmation. This is the entire test duration, not per-request latency.
- The focused local journal/guard/work-pool/process suite passed 52 tests and
  37 subtests in 8.23 seconds before the final broad run. Coverage overlaps.
- Root repository checks, all 29 Desktop Node tests, Desktop structure and diff
  checks passed. Main was fetched and synchronized through `86d343fe3`.
- Source/package metadata is Desktop 1.1.30. No installer/APK was produced, this
  version was not deployed, and no existing pairing/history was changed.
- The original Desktop process remained alive and its health endpoint returned
  ready/ok after testing. The previously denied phone-test launch was not retried
  or bypassed. There is no new phone or physical multi-host acceptance result.

Neither these local successes nor earlier normal S20U tests prove automatic
offload/recovery or the complete App-to-worker MQTT path. The overall goal remains
open until those requirements are wired and verified against real devices.
