# Android #3262 Durability Follow-Up

Android merge: `07156a44cd4494b6121a7d0ea255aa16210f905f`.
Earlier iOS transport adaptation: merged PR #3326. Do not describe this follow-up as a newly implemented full bidirectional MQTT port.
Incremental predecessor: iOS #4530, `03b6b3aee4ddfe50fd859d4063ec4361f86e29cb`. This main-targeted branch is cumulative; its full-main diff is not this independent delta.

## Confirmed Existing Behavior

Native route replacement already retains same-identity handshake state, observes a disabled-to-enabled binding transition and wakes only authenticated ready peers. Subscription refresh/outbox wake already occurs on successful local and received approval. Existing native route fixture sources cover warm handshakes, missing authentication and disabled ingress. None of those kernels are reimplemented here.

## Remaining Gap Fixed

The native approval method previously ignored encrypted save failure and returned success with a verified contact in memory. Callers could then enter their success path to refresh/recover messaging without a saved approval.

Capture the request/contact arrays before mutation. If save fails, restore both and return false before adding the system notice or returning success to those callers. Preserve previous peers and all messages. A later successful retry follows the original path. No identity/Signal key changes, handshake reset, route bypass, contact deletion, subscription polling or encryption weakening.

Four changed Android source files are pinned and mapped to the exact existing/new native dispositions. Only the approval transaction and native failure fixture sources change in production/test code; supporting transport, cryptography, routing and existing UI call sites remain exact.

## Limits

Source contracts and project structure checks do not prove durable approval on a device. Failure/reopen/retry fixture sources are added but not executed. Windows has no Xcode: no Swift type checking, XCTest, real disk/Keychain fault, callback timing, live MQTT bidirectional delivery or device acceptance is claimed. No IPA, version, Android or Desktop change.
