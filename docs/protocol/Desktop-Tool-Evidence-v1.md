# Desktop Tool Evidence v1

Contract: `galaxyssi.desktop-tool-evidence/1`. Capability: `desktop_codex_tool_evidence_v1`.

## Scope and guarantees

The paired-phone Codex app-server execution path records completed `commandExecution`, `fileChange`, `mcpToolCall`, `dynamicToolCall` and `webSearch` items before the bounded progress renderer processes them. Only actual provider events are accepted. Reasoning, plans, assistant messages, generated-image binaries and arbitrary model-reported receipts are not observations in this adapter.

Each record binds the authenticated phone route, client conversation, task, client turn, contact, dispatch source message, Agent and execution generation. Provider thread, turn and item IDs distinguish individual operations. The canonical original provider item is retained without the UI's 100-event or metadata truncation; provider-side truncation cannot be reversed. Capture does not fetch additional source pages or claim that a whole website was read.

The host marks records `execution_observed_not_claim_verified`, with `coverage=provider_payload_as_received`. `outcome=returned` means an operation returned, not that its claims are true, a test passed or an artifact is valid. Nonzero process exit codes, explicit failed/cancelled statuses and reported tool errors produce `outcome=failed`. Models cannot set the host scope or trust classification using fields in tool output.

## Persistence and failure behavior

Encrypted originals and authenticated descriptors live in separate indexed tables in the existing Run SQLite database. Capture checks durable task identity, execution generation and worker ownership in the same write transaction as all evidence pages. Repeated identical completed items return the original reference; changed content under the same provider-item identity is rejected. Another generation, route, member dispatch or provider turn cannot borrow the reference.

New evidence is not admitted to terminal/paused/takeover tasks. Exact prior observations remain replayable. Deleting the owning task cascades to its evidence and pages. An evidence storage failure does not change a completed tool result, manufacture a durable receipt or rerun its side effect. Current coverage is explicitly incomplete; the index always declares `provider_history_complete=false`. This adapter does not reconstruct events lost before capture or automatically retry a failed archive write.

This initial adapter covers the paired-phone Codex callback path. Worker-leased/remote-worker execution must use its own authorized writer adapter, rather than bypassing the lease fence. Other Agents, native Desktop tools outside this path and Android collaboration-ledger import are separate follow-up work.

## Read-only MQTT queries

Requests use the existing authenticated/encrypted application transport. No new broker, subscription, periodic poll, durable response queue or model execution is added. The requester owns timeout/retry. `agent_task_evidence_request` is replay-safe; responses are `agent_task_evidence` and are not persisted into a second outbound queue.

All requests require nonempty string IDs (at most 200 characters):

`client_route_id`, `conversation_id`, `task_id`, `turn_id`, `contact_id`, `source_message_id`, `agent_id`.

Also required: positive integer `execution_generation` and a 1-128 character `request_id`. The route must equal the authenticated paired client. Every other identity field and generation must equal the durable current task, including for completed-task reads. A stale generation is not silently rebound. Malformed requests are rejected; valid but mismatched references return `status=unavailable` without content.

### Index

Set `mode=index` and `after_sequence=0` initially. Responses contain up to 20 immutable descriptors, a monotonic `next_sequence`, and `has_more`. Continue using the last returned cursor; no total-observation cap is imposed. The page size is a transport bound, not a task or research-step limit. The index contains hashes, types, outcomes and timestamps, not raw commands, results or private identifiers.

### Original payload page

Set `mode=page`, the exact `evidence_id` and `sha256` from a descriptor, and zero-based `page_index`. Responses include `data_b64`, `page_sha256`, `page_count`, `total_bytes` and the full-body `sha256`. Each decoded page is at most 16 KiB. Authenticate the transport, verify page hashes, concatenate in order and verify total bytes and full SHA-256 before importing the original. UTF-8 decoding happens after concatenation because a character can span page boundaries.

The original JSON contains the contract, host scope/generation/trust, coverage and `observation` with provider identity and unmodified operational item. Consumers must preserve that provenance and cannot promote it to independent scientific validation. Android import must additionally resolve the exact managed-member dispatch and group authorization; that consumer is not included in this initial Desktop provider.
