# Android #4276 iOS Port

Android merge: `ff3e2d0c4cd9c003dfa1ae33d06c3ae21ed0ceff`.
Incremental predecessor: iOS #4527, `8b7db40a3b6ce518ff17ab21b65478687fce9ad0`.
The main-targeted branch is cumulative; its entire main diff is not an independent #4276 change.

## Fixed Gap

The previous iOS Agent entry admitted ordinary nonprivate conversations and projected up to three global concerns. Android #4276 instead restricts its health surface to an independently bound private concern conversation. The native gate and surface now enforce that boundary.

- Active, private, tracking-paused, unmerged, noncollaboration session with a canonical health-care UUID topic is necessary but insufficient: the encrypted discussion thread must bind that exact conversation and concern.
- A new optional conversation ID in the existing encrypted Health discussion thread is backward-compatible. Existing discussion turns, payloads, approval, research and profile-sharing logic remain unchanged.
- Opening locally reuses an exact durable active binding, otherwise creates an agent-created private conversation and pauses tracking before binding. Database persistence is checked, expected old thread/binding prevents stale overwrite, and failed new-session binding cleans up that new session.
- The local open helper never switches chats, dispatches a model request, picks a provider, grants online access or authorizes research. The explicit detail command separately navigates to the existing Agent page. Empty newly created conversations are persisted before navigation.
- Only the bound concern and its own priority warning can appear. Conversation/owner/background/protected-data changes clear prior surface state; cancellation and captured revision/conversation checks reject stale loads.
- The existing dedicated iOS Health discussion review UI remains an explicit action with its own transcript and approvals. This port does not automatically merge that transcript into generic Agent messages or bypass its data review.
- Exact English/Chinese Open Health Agent pair is in a dedicated table. No Android/Desktop/version changes or IPA.

## Evidence And Limits

Sixteen changed Android files are pinned and individually mapped. Scope, binding and legacy optional decode fixture sources were added to the existing native test target but not executed. Source/resource contracts preserve the generic Agent layout, transport, existing archive behavior and Health approval kernels outside the additive binding.

Windows has no Xcode. No Swift type checking, XCTest, actual encrypted reopen/session reuse, native UI/late callback/background/gesture behavior, real model dispatch or consent/device acceptance is claimed.
