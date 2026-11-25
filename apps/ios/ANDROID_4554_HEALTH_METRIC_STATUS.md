# Android #4554 Health Agent Metric Banner

Reference head: `67e7293fa8988e305ecd0b036887d6e49ab812e5`.
Independent iOS base: main `ee17e7cac043350e3f65c10ba025ecf55cde10c7`.
No unmerged About/search/settings/Health tool-loop PR code is included.

## Production Alignment

- Replace the expandable private Health Agent panel with a read-only metric title and current measurement. Remove stage, comparison/history summary, priority label, chevrons, inner scrolling and all expanded body actions from this banner only. Do not repurpose ordinary conversations or the main composer/transcript.
- Read measurement, unit and report reference from the same bound concern assessment, never a separate/latest/other record or its comparison. A removed source or blank value has no measurement/reference line. A missing reference adds no separator or invented guideline range.
- Append the current measurement unit only when the raw reference parses as a numeric laboratory comparison/range. Keep qualitative, already-unit-bearing and unparsed reference text unchanged. Reuse the existing laboratory notation grammar; no measurement conversion, clinical assessment or report truth claim. Render the localized reference inline as secondary smaller text, retaining full wrapping and Dynamic Type.
- Retain the existing owner/protected-data/active-scene/private exact-conversation binding, archive permission, record-change notifications, revision/cancellation and stale-load guards. Remove only now-unused expansion/priority/sheet presentation state and the old viewport-height parameter. iOS retains its existing local-care permission model; no Android permission flag is fabricated.
- Align the Android surface's existing read-failure/retry behavior: clear all previous measurement text, show only a localized non-data reload button in the current private session, and rerun the same guarded archive load. Valid missing bindings hide the banner instead of becoming an error. Background/lock/account/session changes clear both data and failure state. Cancellation/stale completions cannot publish a failure for a replacement session. This fallback action is outside the read-only successful metric panel.
- The complete Health center/detail/research/plan/follow-up/target/answer routes, backing records, consent, supervisor and discussion models are unchanged. Users still open reviews and discussion through those existing Health center routes. This PR adds no model/tool/network execution or data migration.

## Evidence and Limits

All eleven Android changed files were inspected: two production views, two localization tables, six device fixture files and Android build/version metadata. Android-only version changes are not copied. Fixture changes reference missing/same-record values, compact/narrow display, private isolation and retained Health center routes; Android execution results are not iOS results.

Replace the obsolete expanded-layout fixture with three new measurement/reference formatting fixtures. Retain all other existing scope/overview/care fixtures. These are SOURCE ONLY, NOT executed. A dedicated source guard compares retained health center/detail and privacy/loading sections, main composer/transcript, backing models and resource wiring against the exact base; it also inventories the pinned Android files.

Windows source/project/grammar checks cannot prove Swift type checking, SwiftUI sizing/VoiceOver, refresh/scene races, native device behavior or exact pixel parity. No native build, XCTest/UI run, CI watching or IPA. The older #4278 expandable-panel source guard describes intentionally superseded UI and is not used as proof of this new contract. Full Android-to-iOS backlog remains incomplete.
