# Optional First Page in Recovery Observations

## Purpose and Rollout

Reply recovery currently discovers terminal task status and then requests the
first archived body page, requiring two serial application round trips. A
recovery client can request the first page with its status query. This is an
optimization of the existing encrypted archive/page protocol, not a new message
transport or permission to rerun a task.

Desktop 1.0.34 implements the producer. Android consumption is a separate next
step: the installed Android 1.0.37 does not request or consume this field yet.
No device latency improvement is claimed by producer-only tests. Ordinary
status inspection must remain metadata-only.

## Request

An `agent_task_recovery_request` can set the top-level JSON boolean
`include_result_page` to `true`. Missing values, `false`, strings and numeric
values do not opt in. The existing query nonce, authenticated client route and
whole-batch identity validation are unchanged.

Only observations whose saved task matches every identity component and whose
status is `completed`, `failed`, `timed_out` or `cancelled` are eligible. Waiting,
running, unavailable or mismatched tasks never cause an archive read.

## Response

An eligible observation may contain `result_page`. Its value is the complete
existing `agent_task_result_page` envelope:

- `request_id`: the enclosing recovery query nonce.
- `page_index`: integer zero.
- `execution_generation`: exactly the observed task generation.
- `client_route_id`, `conversation_id`, `task_id`, `turn_id`, `contact_id`,
  `source_message_id`, `agent_id`: identical to the observation.
- `type`: `agent_task_result_page`; `status`: `ready`.
- `sha256`, `total_bytes`, `page_count`: immutable complete-body manifest.
- `page_sha256`, `data_b64`: the first page checksum and bytes.

The archive page size remains 16 KiB. A one-page body can be recovered without
a separate page request; larger bodies continue requesting subsequent pages
with the same pinned digest. This does not acknowledge or delete the archive.
The existing durable result-receipt protocol remains required after acceptance.

The aggregate response, measured as compact UTF-8 JSON, has a 32 KiB budget for
attaching pages. The metadata and every attached page count toward that budget,
including JSON property overhead. If metadata already exceeds the budget, no
pages are attached and all original observations are retained. This is not a
reply-size limit or an MQTT ciphertext-size limit: encryption, wrapping and
padding add their own wire bytes. A batch must not multiply the budget by its
number of items.

Missing, acknowledged, corrupt, busy or oversized optional pages are omitted.
Normal status observations are retained. An optional read does not initialize
a missing archive database or wait behind another in-process archive operation.
Filesystem/SQLite read latency is still possible once the archive lock is
available; this is not a hard deadline or a lock-free I/O claim.

No task execution, provider recovery, result reconstruction or filesystem scan
is performed to populate an optional page. A missing archive can still use the
existing explicit page-recovery path. Diagnostics never include page content;
optional-read errors log the exception class only.

## Consumer Requirements

The Android consumer must authenticate the Desktop, query nonce and full outer
identity as before, then verify the nested page nonce, identity, generation,
type and page index. It must use the existing page-size, manifest, page hash,
complete-body hash, terminal-status and current-execution checks. Receiving an
inline page is not sufficient to publish a reply or claim durable acceptance.

An absent or invalid optional page must leave ordinary page retrieval available.
A valid first page can enter the encrypted checkpoint path and resume normally
after process death. It must not create a plaintext temporary file, a duplicate
reply, an early result receipt, or a synthetic network page-RTT measurement.
Manual status inspection must not opt in and must not expose page bytes in the
chat transcript, model context or system notifications.

## Verification

Producer tests use actual encrypted SQLite archives, including multi-page
Unicode bodies and terminal failures. They cover opt-in semantics, all identity
components, generations, nonce binding, aggregate/exact UTF-8 byte boundaries,
missing/acknowledged/busy archives, lock release on errors, and the actual MQTT
dispatch function with isolated mocked transport authentication.

These are backend contract/integration tests, not a live broker/provider or
phone acceptance run. Android integration and real paired measurements must
precede any claim that one round trip was removed on a device.

Validation on 2026-09-07 (base main `2acc2de48`):

- 159 backend tests and 119 subtests passed, including 22 new producer tests,
  with a fresh isolated `GALAXYSSI_STATE_DIR` established before imports.
- Regression modules include query/archive/receipt/terminal recovery, MQTT
  dispatch, timing, route isolation, transport probes and existing voice timing.
- Desktop checks: 29 tests passed and structure checks passed.
- Repository and whitespace checks passed.
- No production backend restart, phone installation, device data reset or
  live-provider request was performed for this producer-only change.
