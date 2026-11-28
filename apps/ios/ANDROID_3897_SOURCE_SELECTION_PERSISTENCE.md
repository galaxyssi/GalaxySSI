# Android #3897: Saved Source Selection

Reference merge: `b7e20fb12e39c4d0566e7e2a16bebbb6bd810b25`.
Independent main base: `c6bad3465c673dfb2dcecb23b095185c129c7447`.
This is an iOS persistence/UI correction found during source-attention parity
review, not a second implementation of the already existing source recovery.

## Production Correction

The HealthKit page updated its visible scope set before attempting the encrypted
selection write. On a toggle or Clear Import Selection failure, the UI could
display the new choice while the saved selection still retained the old one.

Toggle/clear actions now publish selection only through the existing post-write
reload. On failure, reread the actual source ledger and retain the error indicator.
If the ledger cannot be read, selection controls are disabled rather than editing
an unknown base state. A localized Retry Sources action reloads source state and
the existing focused-scope import history; it does not authorize or query HealthKit.
Retry is disabled while a read/import operation is active. Clearing selection
still immediately cancels the current preview/read even if saving the selection
later fails. Acknowledgement still uses the exact incident and current saved state.

Require the active scene before source-state writes. Backing encryption, atomic
write, equality/no-change notification semantics, selected-source filtering,
read outcomes and current permission/request/import boundaries are unchanged.
Android's selection-change notification behavior is the reference; its
SharedPreferences storage implementation is not copied into iOS.

The newer Android Health overview no longer renders the old attention section.
This patch does not restore that superseded layout, change the iOS overview or
infer HealthKit read permission from an empty query.

## Verification Boundary

The checker pins the exact complete view delta, retained records/source/query/
overview implementations, the existing localization key and eight negative source
mutations, including optimistic UI writes and a retry that starts a query.
These are source contracts, not executed storage-fault, notification, SwiftUI or
HealthKit tests. No Swift build, XCTest, device/UI acceptance, CI monitoring or
IPA is included. Cross-process transactions, metadata-failure retry execution
and the wider Android/iOS backlog remain unverified or incomplete.
