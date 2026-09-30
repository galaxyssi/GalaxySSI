# Preserve First Artifact Receipt Evidence

## Observed problem

Active3 A008 turn 4 in `active3-warehouse-image-20260930-v1326` received and
saved its 149,279-byte PNG after an additional 65.573 seconds of artifact wait.
The original report records reply settlement at 77.925 seconds and verified
artifact availability at 143.694 seconds (including save verification).
The saved SHA-256 is
`63c8569dbdbc29dcd271596f8e9c1dec58cf6f2cc2e11689e8ac69986672dd62`.

The corresponding Desktop ledger later showed creation at 1790701563 and
`stored_at` at 1790701949. That is not evidence of a 386-second first delivery:
`acknowledge_artifact` overwrote `stored_at` on every accepted duplicate receipt.
It also rewrote the complete ledger twice for receipts whose cleanup was already
finished. Existing records cannot reconstruct their overwritten first receipt;
this change does not edit the user's historical ledger or fabricated timestamps.

## Change

- Preserve the first successfully persisted `stored_at` timestamp on retries.
- Return successfully without a disk rewrite only after route, hash, stored
  status and authenticated delivery scope checks pass, and the matched entry is
  already stored with cleanup complete.
- Incomplete cleanup still retries. Its later `completed_at` remains distinct
  from the first receipt time.
- Failed receipt persistence still prevents source cleanup; its later successful
  retry establishes the durable receipt timestamp.
- Keep the existing ledger lock, ownership boundaries and all-recipient cleanup
  checks. No extra network messages, polling, queue capacity or background worker.

Desktop version is 1.3.29. Version 1.3.28 is used by the independent pending
attachment-recovery diagnostics PR #3288. Avoid downgrading this version when
integrating that PR. Android is unchanged.

## Validation

59 isolated backend tests passed in 8.602 seconds:
`test_artifact_delivery`, `test_artifact_delivery_ownership`,
`test_blob_artifact_source`, and `test_blob_artifact_peer_receipts`.
Five new regressions cover duplicate no-write behavior, independent transfer
scopes, cleanup failure/retry, failed initial persistence, and rejection of an
invalid receipt even after a valid receipt completed the transfer.
Tests use temporary real files and ledger persistence, never the running Desktop
task database or user workspaces.

The running Desktop remains the older 1.3.23 process. This fix is not deployed to
that process and is not a claim that the 65.573-second transport tail is fixed.
Current source already contains unit/currency grounding rules; the old-runtime
A008 content failures do not verify those newer rules. Updated-runtime real
MQTT acceptance remains pending. Active3 has no configured DeepSeek target, as
confirmed by the opt-in device preflight; no model call was made by that check.

The frozen 100-case/1100-turn campaign, including original failed observations
and remaining follow-ups, remains incomplete.
