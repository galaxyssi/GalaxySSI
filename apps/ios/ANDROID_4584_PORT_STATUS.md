# Android #4584: Progressive Tool Catalog

Reference: merged PR #4584, source head `51185d5a1ab8f9793b25944e03ad1f878548fe84`,
merge commit `6cc7c65407c0b5b822a7932f3c4e3c5797754310`.
Its 22 changed files and hashes are pinned in `ANDROID_4584_PORT_COVERAGE.json`.
iOS baseline: main `5f60bac1b8571768f6f12f426dee5950c6f87bd0` (merged #4585).
This is PARTIAL integration. Interactive MQTT delayed copies are now wired at
source level below; supervised ephemeral answer previews remain outstanding and
must not be counted complete. Native transport acceptance is also unverified.
Continue those portions in this same corresponding iOS PR, not a duplicate PR.

## Actual Prerequisite And Integration

iOS had no general `galaxyssi.tools.discover` or `galaxyssi.tools.describe`
executors. Its separate local-model readiness helper is not an equivalent
general discovery API. Add real read-only native definitions and executors to
the normal phone catalog and runtime registry before hiding large tool manifests.

The invoking registry supplies metadata through the actual invocation object.
Executors do not capture the registry that installed their definitions: subset
registries must not inspect the parent's hidden tools. Existing input validation,
consent/permission admission, timeout/cancellation, replay and audit code is
unchanged outside this read-only callback attachment. Discovery never executes
another native tool, installs a dependency or grants a consent.

Discovery includes unavailable registered metadata, searches IDs/titles/
descriptions/capabilities using the reference's token and language-alias rules,
returns default 20/max 50 rows and carries a query/revision/last-ID cursor.
Availability timestamps alone do not invalidate cursors; real contract/status/
reason changes do. Unknown or stale cursor boundaries fail explicitly. Zero
metadata hits do not prove absence. Description rows are bounded; describe
returns the selected exact contract value, including null, through a strict
JSON Pointer with escaped keys and canonical array indexes.

## Planning View

For an ordinary eligible catalog larger than 12 entries, retain direct native
web retrieval and both inspection entry points plus at most four distinct
recently completed or described tools that remain eligible. Report available
families and compact callable argument signatures with required markers, small
enums and array item types. iOS uses its existing combined image/news search
schema and raw web-search entry point; this patch does not fabricate Android's
separate native image-search alias.

Development/runtime continuation and phone-control intent retain the original
inventory path. Small catalogs or missing inspection entry points also fall back
to the original path. Selection/availability/runtime filtering still happens
before the progressive view. No separate execution allowlist is added. The
planning parser continues validating against the full actual request catalog.

The iOS prompt builder has no Android manifest cache to invalidate. It renders
from the current eligible descriptors and current execution history each time.
Use structured header/rows in the existing prompt-budget renderer, so compaction
keeps whole callable signature rows instead of cutting JSON or dropping a large
header containing all tools. Inspection/direct entry points precede recent rows.
Preserve the existing goal, dialogue, history, evidence and completion contracts.

## Verification Limits

Nine Swift fixture methods authored and registered, NOT compiled/executed:
invoking-subset isolation, metadata versus consent/execution, escaped/null/array
pointers, query/revision cursor binding, truthful zero matches, large/small/
missing-entry fallback, completed/recent-four carry-forward, callable signatures
and the actual prompt build retaining goal/dialogue.

The new JS source guard pins all 22 reference files, declares the exact registry/
invocation/catalog/prompt hooks, and compares the remaining production source
against main. It retains execution journals/effect/JSON kernels through explicit
newer MQTT normalizations; the stream preview path is still unported. These are source checks, not Swift type checking,
model compliance, actual discovery, privacy, latency, network or device evidence.
No native build, XCTest run, CI monitoring or IPA is included.

## Interactive Desktop Request Copies

The actual journal send drain now requests a local scheduling classification
after ordinary send authorization. The runtime identifies verified Desktop
connector traffic with an exact current destination and registered complete task
identity, then repeats its existing current-owner authorization. The callback
defaults to false for other callers; ordinary peer messages and attachment
control packets do not opt in. No user/model payload field enables this mode.

Pass the in-memory flag onto the direct delivery job, not into a durable record
or wire schema. iOS's existing Desktop Agent requests are `message`, rather than
Android's `final`, so this local scheduling exception recognizes both classes
without reclassifying the wire or changing transcript/completion reducers.

For encoded packet bounds up to 256 KiB, schedule authorized backup paths at
250 ms intervals after the primary. The original resume/subscription/epoch/
packet/headroom filters run before candidate selection, and every physical copy
retains its existing route authorization check, Signal content identity and
per-attempt envelope. This does not add a new per-copy task-owner transaction or
an exactly-once remote-effect guarantee. Larger packets, chunks, progress and
default noninteractive hedge timing keep their existing behavior. Fragmented
messages do not take this direct-delivery exception.

The unchanged dispatcher still commits a verified peer receipt before cancelling
copies; a broker PUBACK or failed receipt commit cannot substitute for it.
Existing wire construction, immutable outbox, completion schema, route-session
and receipt kernels remain unchanged. Six additional Swift fixture methods are
authored only: authorized generation filtering, packet/class bounds, resume/
subscription gates, actual 249/250 ms job scheduling with shared identity and
receipt cancellation, delayed route permission changes and failed receipt commit.
No fixture was executed and no live latency/reconnect/capacity claim is made.

At this checkpoint, twelve related JS source-contract guards passed, including
interactive hedge, progressive catalog, journal Codex, native rich replies, raw
attachments, document input, owned status, pre-shadow, usage, health, provider
ranking and observation timing. `npm run check:ios`, changed iOS Han placement
and diff whitespace checks passed. These are not an all-repository or native pass.
