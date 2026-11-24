# Android #3169 Cloud Entry Navigation

Android merge: `ee66cb9623c40613aefc07fd54bb71924efb8940`.
Incremental predecessor: iOS #4531, `2970b645a07d310a246d5e80e27c5a76a88157bc`.
This branch targets main and includes unmerged predecessors. Its full-main diff is not this independent increment.

## Implemented

- Add Cloud Provider, then Scan to Add, above resource summaries and existing Desktop/local/cloud lists, whether or not providers exist.
- Reuse the existing onboarding and automatic scanner. Remove duplicate add-provider rows from the cloud list.
- Configured cloud entries in both Nodes and Resource Routing open Contact Profile first, with the existing explicit Message action.
- Add a separate Configure Model navigation row in cloud contact details. Reuse the existing configuration editor; opening a profile does not select a model or edit a credential.
- Keep provider asset rendering, downloaded models, local runtime, readiness/routing policy, profile actions and storage unchanged. The Models/Nodes page already has no strategy section; the separate Resource Routing policy page remains available.

## Not Claimed

This is a scoped partial adaptation, not completion of all #3169 settings visuals. The profile hero title/subtitle centering and full icon-tone treatment across legacy subpages remain to be compared and implemented separately. All 11 Android changed files are inventoried, including deferred visual work and Android-only version/device fixtures.

Source contracts, project checks and grammar parsing are not UI or runtime proof. Windows has no Xcode: no Swift type checking, XCTest, native navigation/back-stack, provider Send Message, persistence, accessibility or screenshot acceptance was performed. No IPA, Android or Desktop change.
