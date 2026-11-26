# Android #4584: iOS Integration

Reference: merged PR #4584, source head `51185d5a1ab8f9793b25944e03ad1f878548fe84`,
merge commit `6cc7c65407c0b5b822a7932f3c4e3c5797754310`.
Its 22 changed files and hashes are pinned in `ANDROID_4584_PORT_COVERAGE.json`.
iOS baseline: main `5f60bac1b8571768f6f12f426dee5950c6f87bd0` (merged #4585).
All three corresponding iOS source integrations are wired in this one branch:
progressive tool catalogs, interactive MQTT delayed copies and supervised
ephemeral answer previews. Native compilation and runtime acceptance remain
unverified. This does not complete the wider Android-to-iOS backlog.

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
newer MQTT and preview normalizations. These are source checks, not Swift type checking,
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

## Ephemeral Supervised Answer Preview

Consume the Desktop's explicit `supervised_answer_preview_v1` partial result
only during the actual `requestPairedPhonePlan` invocation. Bind profile,
invocation token, owner, numeric source, verified contact/Desktop/route, complete
conversation/turn/task identity and execution generation. Require running state,
literal boolean user visibility, bounded non-control prose and increasing
sequence. A new invocation cannot inherit an earlier invocation's preview.

The journal projection checks the current authenticated contact first. Both it
and the legacy Signal receive path intercept marked previews before ordinary
progress, raw streaming and transcript persistence. Unknown or stale scopes do
not create a preview or complete a task. Existing encrypted transport inbox
staging remains: this is not a claim that transport bytes never touch disk.

Keep at most 32 runtime scopes, clear them on invocation exit, profile changes,
foreground loss, protected-data loss and plaintext presentation clearing. Private
or Health-related sessions are excluded. Display plain text only beside the
exact outgoing conversation/turn, never as a ChatMessage, TTS request, knowledge,
backup or final-result mutation. The existing final planning parser is unchanged.
Correct the existing misplaced turnStartMillis initializer argument at this UI
call site by passing it to the transcript messages view that actually owns it.

Desktop's prose extraction, diagnostic removal and progress-credit reservation
remain Desktop producer responsibilities, not new iOS server implementations.
iOS consumes the defined format through its existing receipt pipeline.

Eight additional Swift fixture methods are authored and registered, not run:
scope/envelope mutations, strict types, control suppression, bounds, monotonic
sequence, canonical sources and journal projection isolation. Together with the
catalog and hedge fixtures this is 23 authored methods, not 23 executed tests.
The preview JS guard freezes surrounding final-result, persistence and transport
paths after the precise integration hooks. Source guards and project checks are
not native compilation, device privacy, interoperability or latency acceptance.

## Source Check Checkpoint

Thirteen related JS scope guards passed: preview, interactive hedge, progressive
catalog, journal Codex replay, native rich replies, raw attachments, document
input, native status, pre-shadow routing, routing usage/health, provider ranking
and connector observation timing. `npm run check:ios` and diff whitespace checks
passed. These checks do not assert an all-repository or native test pass.
