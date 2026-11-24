# Android #3119 Routing Admission

Android merge: `e7c6af6ef3eed21c7fb697b4458d1cf742833dc4`.
Incremental predecessor: iOS #4533, `ddcb2a69acd02ea12d20fb469e779d4d87b85a4f`.
This branch targets main and includes unmerged predecessors. Its full-main diff is not this independent increment.

## Implemented Boundary

When a routing decision exists, intersect connector targets with its exact primary/fallback target IDs before availability filtering, heartbeat recovery, preferred-target lookup, quality calibration or baseline fallback. Catalog-only resources are informational, not admitted candidates. An explicit preference cannot override this boundary. No admitted reasoning target means nil, not a fabricated catalog candidate.

When no decision is provided, existing capability/default/recovery behavior stays unchanged. Explicit admitted preferences, device rejection, required capabilities, no-route decisions and recoverable heartbeat logic remain in place. This patch does not generate new privacy/budget/capacity decisions or assert that existing decisions cover every policy.

Native regression fixture source covers excluded preferred/catalog targets, an unavailable admitted primary, admitted recovering versus excluded healthy targets, and tool-only decisions. Existing admitted-preference and phone-tool-with-connector-fallback fixtures remain unchanged. Neither old nor new native fixtures are executed on Windows.

## Still Incomplete

This is NOT completion of Android #3119. Main service selector entry points still pass nil decisions; their existing behavior is not changed by this non-nil admission boundary. The header currently derives Auto from display/live/session labels and can default to Codex; it is not yet backed by the Android exact conversation target/turn store. Healthy-primary short-circuit scoring, exact header-to-dispatch identity, stale-turn update rejection, fresh fallback ranking on immediate/asynchronous failure, deferred timeout discovery, parallel parameter preservation and attachment conversation scope still require dedicated current-code comparison and integration. Do not infer their completion from the source inventory or these fixtures.

All 17 Android changed files are pinned with explicit dispositions. Native services, header, selection, planning and quality-ranking implementations are frozen to the predecessor for this increment. It contains no UI, identity preference, transport, credential, version, Android, Desktop or IPA changes.

## Verification Limits

Source contracts and grammar/project checks do not establish Swift type correctness, executed XCTest or real routed delivery. No Xcode, native/network/device acceptance, ten-conversation test, privacy/budget gate execution or runtime fallback verification is claimed.
