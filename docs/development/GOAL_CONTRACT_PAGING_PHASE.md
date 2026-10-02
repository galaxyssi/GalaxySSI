# Durable Goal Contract Paging

This isolated slice adds host-owned goal-contract snapshots, immutable dispatch
bindings, paging, and optional delivery accounting. It does not integrate runtime
prompts, cloud tools, native tools, acceptance, or scheduling. The parent owns
those changes and their integration tests.

## Authority Boundary

Construct `CollaborationWorkspaceAccess` from the host execution context, never
from model/tool arguments. Retrieval requires exact snapshot group/run/turn and
an immutable binding for group/run/turn/node/person. Knowing a different snapshot
hash in the same run does not grant access. Round and dependency nodes cannot
broaden this binding. Contract text is shared host input, not member evidence;
no workspace evidence-read policy is relaxed.

The Android constructor checks current group membership and calls
`CollaborationEvidenceLedger(context).authorizes(access)` on every operation,
passing the complete access unchanged. The ledger must authorize the exact
group/run/turn/node/person/round/dependencies tuple through its host-owned access
index; no field is dropped or normalized and no historical-turn fallback is
used. This path does not consult the default `EncryptedAgentTeamExecutionStore`,
so an independently backed run store is not mistaken for an unauthorized run.

The parent owns the ledger's O(1) authorization lookup and atomic access-index
write in `ledger.bind`. The worker must bind its exact access in the ledger
before prompt construction and before invoking contract publication, binding or
retrieval. Missing or mismatched ledger authorization fails closed; there is no
default-run-store fallback. A pure rows constructor requires an explicit
`(CollaborationWorkspaceAccess) -> Boolean` host authorizer; there is no allow-all
default. Never populate access from JSON arguments or model output.

## Host API

```kotlin
val store = CollaborationGoalContractStore(context)
val descriptor = store.publish(hostAccess, originalGoal, preservedCriteriaJson,
    contextSections = mapOf("roster" to fullRoster, "previousAssessment" to fullAssessment))
// Check status == "ok" before reading any fields; never substitute an empty contract.
val pinned = store.bind(memberAccess, descriptor.getString("snapshot_id"))
val recoveredDescriptor = store.lookup(memberAccess)
val page = store.read(memberAccess, opaqueCursor) // "" starts at page zero
// Only after the exact page has been successfully delivered by the host transport:
store.recordDelivery(memberAccess, page.getString("snapshot_id"), opaqueCursor, page)
```

- `publish(access, goal, criteria, contextSections = emptyMap())` creates or replays
  an immutable snapshot. It does not bind a reader. Inputs must be host-preserved
  data. It accepts initial `[]`; malformed or invalid criteria return
  `status=rejected, reason=invalid_criteria`, with no valid criteria/snapshot hash.
- `bind(access, snapshotId)` is host-only, durable and idempotent. An already
  bound access cannot switch snapshots (`access_already_bound`), even in a later
  round. Use a new host dispatch node for changed criteria or context.
- `lookup(access)` returns only the descriptor for that exact pinned access.
  Model-facing tools take **only cursor**, never scope, member, or snapshot ID.
- `read(access, cursor = "")` resolves the pin internally. The explicit host
  compatibility overload `read(access, snapshotId, cursor)` also enforces the pin.
  Snapshot ID equals snapshot SHA-256, not an unverified model-supplied label.
- `recordDelivery` and `recordInlineDelivery(access, snapshotId, pages)` verify
  the complete page payload through canonical JSON equality and the exact reader
  binding. Neither is a model tool. Inline registration requires the actual
  complete page objects included inline, not just a descriptor or a truncated
  snippet. Reading alone never creates delivery records.
- `delivery(access, snapshotId)` returns counts and the first undelivered cursor.
  A complete delivery ledger is explicitly **not comprehension**, acceptance,
  independent review, semantic coverage, or scientific verification.
- `remove(groupId)` and `remove(context, groupId)` remove all group snapshots,
  bindings, cursor keys and delivery records. Removal is a host lifecycle action.

All rejected JSON responses omit content and hashes and use fixed reason codes;
exception messages and contract content are not logged. Do not turn rejection
into a successful empty response at the integration boundary.

## Snapshot And Wire Format

Snapshots preserve the full original goal, exact raw criteria JSON, the semantic
criteria hash from `CollaborationSemanticGoalCoverage.criteriaHash`, and the
mechanical source IDs/exact texts from `CollaborationSemanticGoalCoverage.source`.
Optional host context sections are also preserved verbatim. New criteria/context
produce another snapshot without mutating old rows or dispatch bindings.

The compact descriptor contains hashes, source/page/context counts, byte budget,
and the first cursor. `context_keys` contains at most eight names and at most 256
encoded UTF-8 JSON bytes. `context_keys_complete=false` explicitly indicates that
the complete directory must be recovered from pages; it never implies absent
sections. No goal, criterion or optional section contents are in the descriptor.

Pages traverse goal, criteria, source, then context (context names sorted by exact
String ordering). `fragments` contain `stream`, `source_id`, zero-based `part`,
`last`, `start_utf16`, `end_utf16`, and exact `text`. Reassemble each stream/source
in part order; require contiguous ranges and exactly one terminal fragment.
Source IDs are host-generated, not model-chosen offsets. A source can span pages.

Context fragments additionally carry `kind=context`, `id=sectionName`, and a
zero-based `context_index`. If a name itself exceeds 64 encoded JSON bytes, it is
losslessly paged first as `kind=context_name` with the same `context_index`; the
content fragments have `id=null`. This exceptional representation avoids an
unbounded name in every fragment. Empty context text still has one final empty
fragment. There is no context filter or separate scheduling mechanism.

Page budgets cover the **entire compact returned JSON encoded as UTF-8**, not
character counts or raw text size: default 8192 bytes, configurable 1024..65536
in the injectable constructor. Pages preserve the snapshot's original budget
after reopen. Transport wrappers/pretty printing add overhead and must have
their own reserved budget. No goal-length, source-count or page-count policy cap
is imposed. Publication currently materializes the host source and pages in
memory, so available memory/storage remain real resource limits, not truncation
rules. Valid surrogate pairs are never split; malformed Unicode is rejected.

The snapshot ID hashes a canonical manifest containing exact scope and the
ordered page hashes. Each read verifies the manifest against the pinned ID and
the requested payload against its page hash. Cursor HMACs bind exact scope,
snapshot, node/person and position; same reader/cursor replay is deterministic
across reopen. Page envelopes include a reader hash, so even the last page cannot
be copied into another member's receipt. Bindings and delivery rows are separately
HMAC authenticated. Missing, mixed or modified requested rows fail closed.

The Android adapter uses `AgentEncryptedDatabase` in private app storage, with
its existing authenticated encryption and storage-key associated data. It does
not write plaintext exports, public files, logs or cloud state. Snapshot batches,
bindings and receipt batches are committed atomically. The injected rows adapter
must uphold atomic durable commit/removal and protect its private cursor key;
it is a trusted host-storage boundary, not an untrusted remote database. Global
in-process synchronization follows existing store conventions; multi-process
writers are not provided by this slice.

## Parent Integration

- Implemented: publish the original host goal and preserved criteria before constructing the
  bounded team prompt. Include complete optional sections via `contextSections`
  before deciding which inline text to omit. Keep the compact descriptor in the
  prompt and bind every member's exact host dispatch access to its assigned ID.
  On retries, recover the existing pin with `lookup`; do not replace it with a
  newly evaluated assessment or roster under the same dispatch identity.
- Implemented: move the worker's `CollaborationEvidenceLedger.bind` before prompt construction.
  Its atomic access index must be available to `authorizes(access)` before any
  contract operation, including publication. Do not substitute a default run
  store or relax round/dependency matching when authorization is absent.
- Implemented: route cloud/native `mode=goal_contract` using host-owned access and **cursor
  only**. Recover the assigned descriptor with `lookup`, never a model selector.
- Still pending: record page delivery only after successful tool delivery. Inline delivery is a
  separate host operation, not an assertion accepted from a model.
- Keep the existing archive as the original-message archive. Do not add an
  arbitrary model-output ingestion API. A host-selected preserved assessment in
  `contextSections` is reference context only, never independent evidence or
  execution authority. Delivery is not comprehension or semantic proof.
- Implemented: invoke group removal for contract snapshots, cursors, and delivery records.
- Do not make all pages fit into a single model context. Future multipart coverage
  must validate unions of host source IDs/parts against the pinned snapshot and
  preserve independent member evidence isolation. This store does not implement
  or certify those semantic union checks.

## Focused Verification

`CollaborationGoalContractPagingTest` uses only injectable in-memory rows and
host access predicates. Cases cover 10k/21k/100k goals, 12,000 clauses, oversized
escaped/Unicode strings and section names, four encoded page budgets, exact source
reassembly, invalid criteria, immutable replay, changed criteria/context, mixed
pages/manifests, cursor corruption, group/run/turn/node/person isolation, immutable
pins, binding corruption, membership revocation, partial delivery/reopen,
inline registration, failed atomic writes and group cleanup.

The 16 paging cases passed in the parent's first 54-case focused run. The integrated
446-case regression also passed, followed by 17 local S26U instrumentation cases
on Android 1.4.20 (1105). Cloud/native callers reconstructed the same original and
rejected forged selectors, incorrect bindings and a removed member. A separate
seed/recover pair reopened 51 pages in distinct processes, preserving the exact
100k-character goal, 21k-character criterion and contexts while rejecting a
deliberately missing page. See the dedicated recovery fixture document.

These results establish scoped storage/access and process persistence, not full
semantic understanding, domain correctness, real-provider reliability or the
unimplemented delivery hooks. Real-provider results remain separately recorded
in the live evidence document.
