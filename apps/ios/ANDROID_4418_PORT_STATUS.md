# Android #4418 iOS Port

Pinned source: `115d6adeb661fd4357fea57517ca92d02ffe1f51`.
Android PR: https://github.com/galaxyssi/GalaxySSI/pull/4418

## Review Scope

Base is main. Inherits OPEN formal #4508 and its documented predecessors; none
is assumed merged. The full main diff contains inherited work, not only this
feature. Incremental review base: `6ca6b7b3e590c39ce7ef45476b2160fe2598f377`
(#4508 head). Only iOS files change; no Android/Desktop edits or IPA.

All six original files have pinned hashes and explicit dispositions:
measurements, two resource XMLs, two device-test references and Android version.
See ANDROID_4418_SOURCE_INVENTORY.json and ANDROID_4418_PORT_COVERAGE.json.

## Implementation

- Replace the atlas metric picker with Related metrics rows for the selected
  anatomy. Show each metric's latest valid, confirmed record, full amount or
  qualitative result, local measurement date and existing provenance label.
  The row selection is explicit. Unrelated metrics never enter this list; missing
  records have no sample values. Pending/denied reads expose no record amounts.
- Latest values are independent of the selected trend window. An older LDL value
  remains visible in the related list even when the month chart is empty. The
  chart receives only the selected metric's valid current records in its chosen
  interval, excluding future/deleted/invalid readings. Existing chart source,
  unit, component and aggregation filters remain separate projections.
- Selecting a row retains the week/month/year selection and requests the existing
  deferred chart reveal. Clear the previous trend/analysis before changing the
  metric. Selecting an empty metric cannot reuse a previous record. The pinned
  Agent action still requires the selected metric/window identity, permission,
  current revisions and actual chart data; the multi-metric latest list is not
  supplied to the Agent handoff.
- Add an encrypted, bounded access ledger in the existing health archive. The
  overview scope names only the anatomy's related metrics and all-time cutoff;
  the trend scope names one selected metric, interval and zone. The index
  projection reads all sources in that interval; existing chart filters may be
  narrower. Log intent before record projection and completion before returning
  values. A readable archive records denied attempts without returning values.
  Audit entries contain scope/consent metadata, not measurement values, and are
  capped at 200. No read-audit notifications or automatic network/export path.
- Surface this ledger in existing Health Privacy history. Preserve the existing
  overview permission boundary. Clear displayed readings on revocation,
  invalidation, background, disappearance and protected-data loss. Refresh on
  owner-matching record changes. Non-atlas trend readers retain their original
  permission gate and data path. Storage failures fail closed.
- Extract/register four exact Android English/Chinese pairs, six native privacy
  labels using existing English fallback/Chinese resource conventions, and the
  two new Swift files plus focused XCTest source.

## Source Verification And Limits

Passed six source hashes/dispositions, exact resource reproduction, metadata-only
audit and permission-before-projection wiring, related/latest versus scoped
trend/lifecycle/Agent identity source checks and inherited #4417/#4414 checks.
Eight changed/added Swift files parsed without grammar errors after conditional
directives were removed. iOS project structure and whitespace checks passed.

Added XCTest SOURCE fixtures for concurrent readings, older versus scoped data,
future/deleted/invalid exclusions, ties, qualitative results, encrypted audit
reopen, denied/unrelated reads and empty/stale/authorized Agent actions. These
tests were not executed. No Android tests, Swift type checking/Xcode build,
simulator/device launch, native permission/storage/scroll/pixel/VoiceOver
acceptance or IPA. Android verification is not iOS evidence. Inherited runtime
and vector acceptance gaps remain; formal PR status is not native certification.
