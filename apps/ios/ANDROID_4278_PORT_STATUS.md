# Android #4278 iOS Port

Android merge: `239692d36820daf678c74226ae7be67c622fc1e8`.
Incremental predecessor: iOS #4528, `8399bf031556b7433074a8135836fd5215ea885d`.
This main-targeted branch is cumulative; its complete main diff is not an independent #4278 delta.

## Changes

- Start with a compact collapsed header: concern/stage, latest value or kind-specific before/after summary, and compact priority status. Both the header and a fixed 44-point chevron control toggle the assessment.
- Keep the toggle outside the independent vertical body scroll. Expanded total height is capped at 300 points and 40 percent of the actual output viewport (excluding main header/composer). Measured header height is subtracted before allocating body height; short body content need not occupy the full budget.
- Put every reason signal, the next step, discussion and maintenance evidence inside the expanded body, with no reason/next-step line limit. Show full priority notice there while retaining its compact header status.
- The body links to the exact concern's existing details, which retain plans, questions, answers, follow-up and research controls. Dedicated iOS Health approval/transcript surfaces are preserved, not silently replaced with generic chat submission.
- Preserve expansion and existing expanded ScrollView identity on same-concern refresh. Existing concern/owner/conversation/background/protected-data clears and late-load guards remain unchanged.
- Import three changed Android label pairs plus four unchanged comparison/priority references. Pin the unchanged presentation/resource dependencies separately. Do not change Android/Desktop, iOS version or IPA packaging.

## Evidence And Limits

Nine changed Android files and five unchanged dependencies are individually pinned/mapped. Source/resource contracts preserve the independent private binding, archive/model/approval kernels and generic main-page behavior except output-height forwarding. Native pure layout-budget fixtures are added but not executed.

Windows has no Xcode. No Swift type checking, XCTest, measured native phone/tablet/Dynamic Type layout, real scroll-offset retention, fixed-toggle reachability, actual background/refresh behavior, VoiceOver/pixels/device acceptance or IPA build is claimed. Android itself records its updated instrumentation execution as pending; it is not substituted as iOS proof.
