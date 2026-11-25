# Android #4543: unexecuted Health reply boundary

Reference: Android #4543, merged as `2a8bb348cea9c9f2e3724951623a62f393ca2e3a`.

This is a partial port, not completion of Android #4543.

## Implemented

- The existing approved Health discussion reply commit path classifies the reserved
  recovery marker and JSON ActionPlan `actions` arrays using the existing plan JSON
  extractor. Classification does not validate or execute a plan.
- A bounded decoded control reply is retained exactly in the encrypted Health turn,
  under the existing owner, thread, turn, destination, consent and revision checks.
  It is not saved as an answer. No full HTTP envelope is claimed to be retained.
- An associated dispatched research job becomes interrupted, not completed. No
  checkpoint or assessment is invented, and the same research trigger is not replayed.
- Exact duplicate receipt commits are idempotent while approval remains current;
  conflicting replies and further scoped reads/tool mutations are rejected.
- Current and archived discussion views display a localized interruption message.
  Legacy answer fields containing the recognized control shape are also withheld
  without deleting their original bytes. These fields are excluded from subsequent
  discussion prompts and reusable research-source history.
- Native fixture sources cover encryption/reopen, exact binding, duplicate and
  conflicting receipts, no completion/replay, legacy display filtering, and
  permission/expiry/size limits. They were not executed on Windows.

## Still required

- Approved Health discussion submission through the standard durable Agent task,
  including a persisted exact grant and provider/model snapshot.
- Grant-scoped initial and continuation planning, no global memory/screen or
  collaboration disclosure, and original conversation/turn reply restoration.
- Standard processing timer, task recovery and native end-to-end acceptance.
- Broader malformed/other control envelopes and oversized response receipt handling.
  Existing response parser and size limits still reject these rather than retaining
  an HTTP receipt; they are not silently retried by this change.

No native compilation, XCTest execution, network/device validation or IPA build
is represented by source-level checks.
