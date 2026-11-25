# Android #3169 Cloud Entry Navigation

Android merge: `ee66cb9623c40613aefc07fd54bb71924efb8940`.
Incremental predecessor: iOS #4531, `2970b645a07d310a246d5e80e27c5a76a88157bc`.
This branch targets main and includes unmerged predecessors. Its full-main diff is not this independent increment.

## Implemented

- Add Cloud Provider, then Scan to Add, above resource summaries and existing Desktop/local/cloud lists, whether or not providers exist.
- The actual top-level Models & Agents hub now lists installed contact-backed targets directly, rather than requiring another category page first. Keep local downloaded models after these entries. Reuse the callable-target catalog, omit synthetic local-runtime probes, remove duplicate IDs and deleted contacts, and do not hide offline installed entries.
- Reuse the existing onboarding and automatic scanner. Remove duplicate add-provider rows from the cloud list.
- Configured cloud entries in both Nodes and Resource Routing open Contact Profile first, with the existing explicit Message action.
- Add a separate Configure Model navigation row in cloud contact details. Reuse the existing configuration editor; opening a profile does not select a model or edit a credential.
- Keep provider asset rendering, downloaded models, local runtime, readiness/routing policy, profile actions and storage unchanged. The Models/Nodes page already has no strategy section; the separate Resource Routing policy page remains available.
- The actual model hub resolves cloud provider marks before generic Agent identities, using provider/ID fields rather than renamed display titles. The existing shared menu renderer uses original-color assets, not status tint.
- Center the profile subtitle and GalaxySSI name in a shared column, place the action chevron outside the title's center, and retain profile and QR actions. Align home voice/memory/skills/general icon tones with the Android semantic groups. Existing grouped/legacy shared native renderers already use supplied icon tones.

## Not Claimed

This is not proof of pixel-identical settings visuals. A full legacy-subpage icon inventory and native layout/device acceptance remain unverified. All 11 Android changed files are inventoried, including these limits and Android-only version/device fixtures. Do not label static renderer checks as executed native UI tests.

Source contracts, project checks and grammar parsing are not UI or runtime proof. Windows has no Xcode: no Swift type checking, XCTest, native navigation/back-stack, provider Send Message, persistence, accessibility or screenshot acceptance was performed. No IPA, Android or Desktop change.
