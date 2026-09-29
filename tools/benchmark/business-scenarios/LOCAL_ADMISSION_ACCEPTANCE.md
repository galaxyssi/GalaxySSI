# Local MQTT admission and artifact retry accounting

## Observed failure

Active3 SM-T575, Android 1.3.26 (1069), Desktop 1.3.23, real Codex run
`active3-warehouse-pptx-20260929-v1325`, A007 follow-up 3 returned a PPTX and
four declared PNG previews. The second preview was still absent after the
existing 90-second attachment observation window. Preserve that delivery
failure; later recovery must not rewrite the original result.

Read-only correlation of the artifact ledger, durable outbox and backend log
identified one pending preview, `ART-007-v04-page-2.png`. The source file still
existed (77,531 bytes). Its durable wire record had six attempts and failed
status. The corresponding publish attempts logged rc=15, followed by retry
exhaustion. The installed Paho constant identifies 15 as
`MQTT_ERR_QUEUE_SIZE`, a local admission refusal, not a peer rejection or proof
that a public broker was unavailable. The artifact was the only pending
unscoped ledger entry, so this sample was not hidden behind a 32-item replay
batch.

The reply arrived in 192,878 ms; attachment observation took a further 90,084
ms; observed total was 286,871 ms. These measurements include instrumentation
and are not isolated broker latency. Content quality and actual UI save are
separate acceptance dimensions.

## Narrow repair

Desktop 1.3.31 treats rc=15 like the existing explicit deferred result.
`mark_outbound_deferred` returns the already persisted message to the queue
and rolls back only the reservation's attempt increment. It does not create
new ciphertext, reset earlier physical attempts, or recreate a message that
was concurrently acknowledged. Real non-capacity failures retain their
previous retry accounting.

The normal worker poll, retention, batch size, global/per-client artifact
inflight bounds, delivery receipts and encryption are unchanged. This adds
no thread, unbounded in-memory queue, extra model request, or larger retry
limit. A continually saturated queue still needs capacity to become available;
this repair does not promise immediate delivery under permanent saturation.

## Regression evidence

The new real-database regression failed before the production change. It
repeatedly refuses local admission beyond the physical retry limit, verifies
zero physical attempts and unchanged ciphertext, then admits the same message
successfully. Additional checks cover preservation of two previous attempts,
a concurrent receipt deleting the record, and unchanged disconnected-error
accounting.

157 isolated backend tests passed in 13.066 seconds across durable delivery,
delivery bridge/dispatch, pool policy, broker-ack capacity, fragment callbacks,
durable chunks and chunk exchange. The runner uses temporary application data,
not the live Desktop delivery database.

The selected Desktop JavaScript regression suite passed 61 tests; the business
catalog/report suite passed 32 tests. `git diff --check` passed. The full
`apps/desktop/scripts/check.js` gate still fails at its line 818 literal
`backendDataEntries` contract: it expects only `web_source_sites.tsv`, whereas
the existing packager also includes `research_contract`. Both files are
unchanged from the fetched `origin/main`; this patch does not claim a green
full static gate or silently change that unrelated check.

## Remaining acceptance

This patch has not yet replaced the running Desktop 1.3.23 instance. No live
outbox records were manually reset or deleted. The existing failed preview
still requires ordinary recovery/redelivery and an end-to-end UI open/save
check after deployment. Unit regression success does not establish that this
historical business turn passed.

The frozen campaign remains 100 cases and 1,100 turns, catalog SHA-256
`945c11225d2f7268e43403c09c7f0bc8158c579168b65e3c32a4b16ba9a113bc`.
