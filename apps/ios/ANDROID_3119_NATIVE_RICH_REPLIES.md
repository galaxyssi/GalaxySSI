# Android #3119: Owned Native Connector Rich Replies

Baseline: main `26e82a54754c11aab4e32c09fc1c389ff1b13628` (merged #4582).
This is an independent iOS follow-up, not completion of Android #3119 or #3007.

## Actual Missing Host Connection

The response resolver already preserves a Desktop reply's `rich_output` in the
settled action metadata. The native final-message producer previously ignored it:
`localNativeRichOutput` handled local tools/captures only. Successful native
connector replies therefore lost their returned rich blocks in the transcript.

The producer now loads the committed managed response by owner. A read-only
policy requires an exact original action/source UUID/profile/local turn plus
managed source/contact/conversation/turn/remote task/agent/owner/generation.
Both reply prose and rich JSON must equal the committed successful response.
Pending, failed, unknown-effect, wrong-scope and non-completed terminal replies
cannot supply rich output. A non-retriable flag alone does not hide successful
output or authorize retry. Existing codec normalization/materialization remains
responsible for rich blocks; no new URI opener or payload format is introduced.

## Artifact Completion And Late Presentation

After a native incoming message is actually persisted, reuse terminal Blob
presentation hydration with the remote contact and numeric source. This covers
an artifact completion arriving before the transcript row. Hydration captures
the current profile and rechecks it after the receiver actor await.

Agent artifact updates now search incoming messages with exact conversation and
turn plus the existing full verified-artifact metadata predicate, including
route/Desktop/task/generation/transfer/URI/hash/size. A later outgoing or
different-scope row cannot consume the search and hide the real target. Gallery
items use the same predicate. The existing updater itself is unchanged.

For non-team numeric Agent Blob scopes, the existing paired-contact, registered
identity, privacy and source-recovery admission additionally requires an exact
verified managed record and generation. Pending owners can receive pre-result
offers; committed owners must have successful matching responses. Existing team
authorization is retained and is not replaced by this generic ledger check.
UUID Agent paths and ordinary peer-chat UUID storage rules remain unchanged.

## Verification Boundaries

Seven Swift fixture methods were authored and registered, covering real native
settlement, owner mutations, pending/failed/unknown replies, local context,
ineligible newer rows, gallery matching and managed numeric scope. They were
NOT compiled or executed. The source guard compares production changes against
the pinned baseline and freezes existing receiver/codec/materializer/ledger
models/journal/transport files outside this follow-up. This is source-contract
evidence, not device, cryptography, network, restart, download or UI acceptance.

No Android/Desktop edits, dependency or wire-schema changes, automatic remote
execution grant, build, IPA, CI monitoring or full-parity claim is included.

Source verification for this change: native-rich/raw-attachment/document/status/
pre-shadow/usage/health/ranking/observation-timing/autonomous/research/background/
live-planning/special-use guards (14) and `npm run check:ios` passed, as did changed
iOS Han-placement and diff-whitespace checks. Historical
`check-schedule-provenance-scope.cjs` fails its old unread-database range equality
after existing health-window additions. That assertion's database input is
identical to current main; neither it nor the historical guard is edited here.
