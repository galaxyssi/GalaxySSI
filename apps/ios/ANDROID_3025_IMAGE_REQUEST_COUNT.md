# Android #3025: image lookup request contract

Reference: Android #3025, merge cef237557f5f8f422f93832a535e3d63e3ba81ed.
Independent iOS base: 8a794e82ebe8f09790e41139295ffb7ac1ee9701 (main).

## Actual gap corrected

The dedicated web_image_search alias previously forced at least six results and
defaulted to twelve, despite its schema allowing one and the ordinary image
search path defaulting to three. Requests for one or two pictures therefore
expanded before the real native registry/provider invocation. Normalize this alias
to the pinned Android contract: default three, clamp 1..12, preserve the exact
query, image vertical, fast profile and fanout three. Clamp Int64 values before
conversion; no new numeric coercion policy is introduced. The alias still returns
candidates, not a promise that the network has enough relevant/valid images.

Current-evidence instructions now distinguish retrieval of existing pictures from
requested image generation/transformation. This is model guidance, not a new
keyword classifier, a forced generator choice or a factual/visual verification
guarantee. No query translation or expansion is added. The prior fast unplanned
research defaults, explicit plans/profiles/limits, weather date rules, caption
guidance, source verification, permission/consent and disclosure paths remain.

## Per-area comparison and remaining scope

- Android CloudWebGrounding: existing iOS simple weather/news, dated-source,
  no-duplicate-caption guidance and unplanned fast defaults are retained; this
  increment fixes the missed dedicated image count and clarifies retrieval intent.
- Android MQTT receive timing: the later #4610 increment adds DEBUG-only probes
  at actual iOS stages; see ANDROID_3025_MQTT_INBOUND_TIMING.md. Existing encrypted
  receipt, replay and dispatch behavior is retained; native timing is unverified.
- Android OkHttp idle retention/HTTP2 pings: the follow-up in
  ANDROID_3025_MOBILE_STREAM_SESSIONS.md adds owned idle-only session rotation
  without lowering active deadlines. No matching HTTP2 ping control is claimed;
  stale-connection and weak-network acceptance remain follow-up work.
- Desktop ACK-credit/coalescing and task priority: backend-only changes are not
  reimplemented in iOS. No encrypted packet deletion, ACK relaxation or concurrency
  reduction is introduced. End-to-end credit behavior is not accepted here.
- Desktop ordered image parsing/captions: the later #4610 increment fixes iOS
  linked-wrapper parsing and case-sensitive artifact identity; see
  ANDROID_3025_ORDERED_IMAGE_REPLIES.md. Creation/transfer ordering and validated
  task-local caption equivalence remain unverified, not completed by this fix.

This does not close all #3025 latency/media work or the Android-to-iOS backlog.
Android/Desktop code and versions remain unchanged. iOS 15 minimum is unchanged.

## Verification boundaries

Five new Swift test methods cover every supported count, default/Int64 bounds,
alias spelling, actual executeTool/registry dispatch and denied permissions,
explicit research-plan preservation, and schema/prompt consistency. The existing
fast-search fixture is corrected from expecting six for a one-image request to
expecting one. Tests are authored only and have not been compiled or executed.
JavaScript source contracts retain surrounding code and validate the intentional
count/prompt change; older source guards normalize only these declared changes.
No native/model/network/UI acceptance, latency measurement, CI monitoring or IPA
is performed. No reports or private device data are committed.

The historical fast-defaults and public-search-parser guards were also attempted
and remain failing on unrelated baseline drift: removed fixed cache-byte capacity
and Health discussion resume hooks respectively. The fast-defaults failure was
reproduced with its source and reads taken from origin/main. Both reported
production files are unchanged against this PR base. No obsolete capacity limit
or old Health behavior is restored to make historical checks pass.
