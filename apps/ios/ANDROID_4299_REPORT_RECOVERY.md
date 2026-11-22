# Android #4299: report recognition recovery

Reference: galaxyssi/GalaxySSI#4299, merge
`62e43e3e8729a91160b4e53d1313d1a866e0bfa4`.

## iOS mapping

- `GalaxySSIHealthReportVision`: validate the envelope strictly, but validate
  individual rows independently. Preserve accepted row identity and order;
  count unsupported metrics, invalid units, invalid fields and duplicates.
  Distinguish malformed replies, no supported rows and no valid rows. Model
  replies cannot supply the locally generated rejection counters. Validate
  stored results separately, including legacy empty-result compatibility.
- `GalaxySSIHealthReportDelivery` and `MqttBusinessTransportRuntime`: at most
  two publications of the same request identity. Retry rejected publication
  after 500 ms; after acceptance wait 20 seconds, then probe admission for up
  to 8 seconds. Only authenticated exact-task absence permits resubmission.
  Active/unknown admission waits another 160 seconds without resubmission;
  remote terminal failure stops. A late terminal reply wins over a probe.
- `GalaxySSIHealthReportCodexExchange`: ephemeral nonce-correlated metadata
  probes bind Desktop, route and all seven task identity fields. Query messages
  omit images, content and result-page requests. Ignore unsolicited bodies;
  never import probe replies as report output or ordinary chat recovery.
  Expiry, cancellation and transport shutdown discard probe state. Existing
  encrypted transport and exact destination authority remain required.
- Recognition jobs persist failure codes, not raw remote/private error text.
  The single-file and selected-file views display localized categories and
  explicit continuation. Each failed file can be continued independently;
  successful files and receipts are not sent again or overwritten.
- Continuation refreshes the exact failed job snapshot and rearms the batch
  barrier before sending. Context prompt-once guards apply only to missing
  sampling fields. Failed confirmation ID sets cannot auto-loop, while a new
  set can proceed. Sampling confirmation stays local and does not resend images.

## Verification boundaries

- Added deterministic XCTest source for publication/admission policy, identity,
  expiry, cancellation, row classification, stored counters, partial import and
  per-file continuation with batch confirmation.
- `npm run check:ios`, changed-Swift grammar parsing and `git diff --check`
  passed on Windows. Grammar parsing is not Swift type checking.
- XCTest execution, Xcode compilation, device UI and live paired Desktop
  MQTT exchange were not performed on this Windows host.
- Changes are iOS-only; no Android/Desktop code, CI policy, IPA packaging or
  automatic merge is included.
