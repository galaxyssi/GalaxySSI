# Android #3119 Routing Admission

Android merge: `e7c6af6ef3eed21c7fb697b4458d1cf742833dc4`.
Incremental predecessor: iOS #4533, `ddcb2a69acd02ea12d20fb469e779d4d87b85a4f`.
This branch targets main and includes unmerged predecessors. Its full-main diff is not this independent increment.

## Implemented Boundary

When a routing decision exists, intersect connector targets with its exact primary/fallback target IDs before availability filtering, heartbeat recovery, preferred-target lookup, quality calibration or baseline fallback. Catalog-only resources are informational, not admitted candidates. An explicit preference cannot override this boundary. No admitted reasoning target means nil, not a fabricated catalog candidate.

When no decision is provided, existing capability/default/recovery behavior stays unchanged. Explicit admitted preferences, device rejection, required capabilities, no-route decisions and recoverable heartbeat logic remain in place. This patch does not generate new privacy/budget/capacity decisions or assert that existing decisions cover every policy.

Native regression fixture source covers excluded preferred/catalog targets, an unavailable admitted primary, admitted recovering versus excluded healthy targets, and tool-only decisions. Existing admitted-preference and phone-tool-with-connector-fallback fixtures remain unchanged. Neither old nor new native fixtures are executed on Windows.

## Scoped Auto Identity And Primary Dispatch

Add optional backward-compatible target/turn state to the existing encrypted native conversation payload. No separate plaintext preference store or display-label-to-ID inference. Preserve conversation timestamps and the unpromoted draft state. Only cache/publish after the database write succeeds. Session removal and encrypted persistence retain their normal ownership boundaries.

Begin binds a Hermes user turn to its exact conversation. Older replay turns cannot replace a newer turn. Dispatch updates require the bound turn and automatic selection; manual updates, missing scopes, archived/merged sessions and unavailable sentinel IDs are rejected. This metadata does not grant provider or transport authorization.

The primary local/cloud/Agent dispatch chain captures one automatic target ID rather than re-ranking independently in each branch. Before the selected branch proceeds, commit its exact ID for the current turn or fail. A healthy eligible remembered primary returns without alternate quality ranking; unavailable or capability-ineligible primaries follow the existing selector. Header reads the same exact target identity and no longer invents Codex or adopts a stale live/session display label. Manual presentation and configuration remain unchanged.

New native fixture sources cover encrypted reopen, conversation isolation, stale turn/replay rejection, manual protection, legacy decoding, exact Auto header identity and healthy-primary selection. These sources are not executed. Source guards do not establish persistence fault behavior or actual routing acceptance.

## Still Incomplete

This is NOT completion of Android #3119. Main service selection still starts without a full scored privacy/budget/capacity decision; this change must not be described as adding that missing policy engine. Fresh fallback ranking on immediate/asynchronous failure, deferred timeout discovery, parallel parameter preservation, scheduled/resumed provider dispatch identity, attachment conversation scope and live failover header updates still require dedicated current-code comparison and integration. Older callbacks can still change legacy display labels; they cannot update the new exact Auto binding without its turn. Do not infer broader recovery completion from the source inventory or these fixtures.

All 17 Android changed files are pinned with explicit dispositions. Manual selection, planning factory and quality-ranking implementations remain exact; only the primary Auto path/header and encrypted session metadata are extended. No transport, credential, version, Android, Desktop or IPA changes.

## Verification Limits

Source contracts and grammar/project checks do not establish Swift type correctness, executed XCTest or real routed delivery. No Xcode, native/network/device acceptance, ten-conversation test, privacy/budget gate execution or runtime fallback verification is claimed.
