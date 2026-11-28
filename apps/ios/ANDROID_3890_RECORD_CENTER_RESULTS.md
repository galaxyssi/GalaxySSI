# Android #3890: record center result display follow-up

Reference: Android merge `7c98635fab8b5c0e27ec0f19c95b94acf0432a61`.
Baseline: main `c6bad3465c673dfb2dcecb23b095185c129c7447`.

The existing iOS record center already provides camera, manual entry, file import,
device/source navigation, pending OCR review, table review/history, recent records,
originals and metric catalog destinations. This is not a replacement of that port
or a claim of complete screen parity. Android's recent row uses
`healthDisplayValue(record.draft)`; iOS still used only the optional numeric field.

## Change

- Reuse the metric catalog's display semantics: reported raw notation first,
  otherwise locale-formatted numeric value; include blood pressure's diastolic
  component and the saved unit only when nonempty.
- Comparisons, ranges and qualitative results are not coerced to exact numbers.
- Keep grouping, ordering, pagination, drafts, navigation, scene clearing,
  notifications, encrypted storage and confirmation gates unchanged.
- No new strings, permissions, model calls or network traffic.

## Validation limits

`node apps/ios/tools/check-health-record-center-results.cjs` checks the exact
approved source delta, catalog formatting agreement, Android reference and eight
synthetic negative source mutations. These checks do not execute Swift or prove
rendered output. Native compilation, localized numbers, comparator/range and
qualitative rows, blood pressure, VoiceOver and device navigation remain unverified.
No native tests, CI inspection or IPA build is performed for this follow-up.
