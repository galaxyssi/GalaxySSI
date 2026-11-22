# Android #4288: in-flight Health consent withdrawal

Reference: galaxyssi/GalaxySSI#4288, merge
`fff9f9ee398299f37734e60fa13e9e5dd2f74da5`.
The Android PR adds production-path device acceptance tests, not product runtime
code. This iOS adaptation strengthens the corresponding persistence boundary and
adds synthetic source tests. It does not claim to reproduce Android's real paired
Codex/WorkManager acceptance run.

## iOS finding and change

Before this change, saving `healthOnlinePermission=nil` immediately rejected old
turns, but durable research cancellation was produced only by a later lifecycle
reconciliation. An app exit before that reconciliation delayed outbox creation.

`setHealthOnlinePermission(false)` now revokes standing research authorization and
records each active paired task's exact cancellation in the same encrypted archive
write as the permission change. The existing research ledger preserves the source
message, route, task, conversation and turn identity. Active jobs become cancelled;
completed historical assessments and user-visible records/messages remain intact.
Repeating withdrawal is idempotent, including recovery of legacy archives where
online permission was already off but a standing authorization remained.

Reenabling online analysis issues a new permission epoch but never restores old
standing consent or dispatches a replacement request. Existing exact cancellation
handoff remains responsible for retiring the pending outbox entry only after local
transport queue acceptance. That acceptance is not proof of remote provider
termination or erasure.

## Source coverage and remaining verification

Six isolated XCTest cases cover withdrawal without a lifecycle wake, archive reopen,
repeated recovery, online reenable, synthetic stale final rejection through the
phone-side production assessment retention API, exact outbox handoff and retained
completed history. They use temporary encrypted archives, synthetic records and
in-memory secrets; they do not touch a real user's contacts or pairing.

Reopening an archive in a new object is not an actual process restart. The late
final is an explicitly synthetic fault and is not attributed to a provider. These
tests do not exercise the encrypted MQTT inbox, delivery tombstone handling, live
transport cancellation, device force-quit or a physical reboot. Those portions of
Android's production acceptance remain unverified on iOS.

Windows verification is limited to project structure, changed Swift grammar,
localization placement and whitespace/merge checks. No Swift type-check, XCTest
execution, iOS notification/provider acceptance or IPA generation is claimed.

This change started directly from main and uses the already merged #4373 synthetic
fixture. It was rebased after #4374 and #4375 merged; its diff contains only this
revocation change, not copies of those feature commits.
