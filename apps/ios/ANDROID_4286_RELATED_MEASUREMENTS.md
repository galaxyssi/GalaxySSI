# Android #4286: consent-scoped related measurements on iOS

Source: galaxyssi/GalaxySSI#4286, merge
`baf90d82f0589e666e80fedd38c5937b88ba3dc3`.
Android #4285 changes a Desktop Python test only and needs no iOS runtime port.
This change builds on the notification implementation in iOS #4373 / Android #4284.

## Consent and sources

- The existing Health research authorization screen offers optional measurement
  toggles. Available normal measurements do not need an abnormal care concern.
- Nothing is selected by default. The confirmation sheet shows the exact selected
  snapshots. Authorizations remain encrypted in the existing Health archive.
- Standing consent fixes metric identities, not forever-frozen record versions.
  Each turn captures current record revisions, history identity, result, unit,
  reference, measurement time, conditions and current record-bound clarification.
- No import filenames, device identifiers, unrelated transcripts, other concerns'
  plans or arbitrary profile fields enter these snapshots. Previously selected
  but now missing sources become explicitly unavailable, not normal results.
- Changes to selected source/context fingerprints change the idempotent research
  trigger. Unselected changes do not change it. Legacy consent has no implicit
  additional measurement scope, and nil optional trigger fields preserve old keys.

## Reads, assessments and actions

- Cloud requests initially include selected current snapshots plus opaque history
  entry tokens, not all selected histories. The existing history function can read
  the requested first page and contiguous older pages, with independent tokens per
  metric and a shared four-read continuation budget. Pages carry record revisions,
  units, individual timestamps and comparison gaps.
- Production transport consumes entry tokens, advances cursors and rejects reused,
  foreign, exhausted or unapproved cursors. Every read and cloud continuation
  rechecks the complete live turn/source/provider authorization.
- Structured assessments must cite the primary current record. They may additionally
  cite only the approved primary baseline or selected current record references.
  The exact selected fingerprints are retained with the assessment.
- Turn start/finish, structured retention, pending-plan review/adoption, attention
  notification presentation/delivery/taps and source reconciliation reject changed
  selected evidence. Revoked standing consent also invalidates related pending
  plans. Nothing here adopts plans or creates reminders automatically.
- Related changes have a separate handoff reason, not a clinical-progress claim.

## Withdrawal and platform differences

- Private conversation history, historical model opinions, scoped plan descriptions,
  action feedback and model-visible question pages exclude material whose selected
  metric scope is no longer authorized. User-visible messages, questions and plans
  are retained. Historical selected measurements are labeled historical.
- Health discussions already live in a separate encrypted archive, not the general
  Agent conversation recall store; this change does not export them into recall.
- Paired Desktop remains the existing read-only, phone-supervised snapshot protocol:
  it receives selected current snapshots and exact assessment record references,
  with `selected_history_read_available=false`. It is not granted Desktop tool,
  filesystem or command access. **On-demand paired Desktop history paging is not
  implemented by the existing iOS private Health protocol.** This is a remaining
  parity gap, not a claim that Android's live paired history tool ran on iOS.
- iOS background scheduling and notification restrictions remain those documented
  for #4373; this change does not make delivery immediate or clinically validated.

## Verification

- Added XCTest source coverage for consent defaults/round-trip, normal options,
  selected/unselected changes, idempotent reassessment, combined record validation,
  encrypted reopen, stale attention, stale/revoked plan rejection, independent
  cursors, the actual cloud read continuation loop, forged payload rejection,
  withdrawal filtering and the read-only paired snapshot boundary.
- `npm run check:ios`, changed Swift grammar parsing, localization-placement and
  whitespace checks are the available Windows checks.
- No Swift type-check, XCTest execution, simulator/device UI check or live provider
  acceptance run was performed on this Windows host. No IPA is generated here.
