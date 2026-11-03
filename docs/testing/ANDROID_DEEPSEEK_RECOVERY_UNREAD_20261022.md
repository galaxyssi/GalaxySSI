# DeepSeek recovery and unread reconciliation

## Scope

Device: Galaxy S26 Ultra (SM-S9480). Updated from Android 1.5.93 (1375)
to 0.1.6.1 (1377), using an in-place installation without clearing app data.
Desktop behavior and model settings are not changed by this patch.

## Observed failures

1. An eight-hour community-information request accumulated 195 replans and
   261 actions. Provider-unavailable failures included 153 Codex failures and
   11 DeepSeek failures. The original request explicitly locked DeepSeek, but
   an older recovery revision dropped that binding. The outer supervisor also
   ignored non-retriable failures and continued asking for another recovery.
   The request began before the previous DeepSeek fix was installed; its
   persisted recovery history was not repaired by that fix.
2. The drone/image request first attempted Codex, then switched to DeepSeek.
   After process death, cold-boot recovery replaced its dispatch receipt with
   a generic interruption result. The cloud action stayed WAITING_RESPONSE
   without a surviving HTTP request. A terminal workspace and a waiting
   session disagreed. The displayed hours were not continuous model inference.
3. An unread token referred to an older assistant acknowledgement outside the
   latest 100-entry transcript page. Opening the latest page only acknowledged
   entries loaded into that page, so this valid but older token remained.

## Changes

- Recover a manual provider/model binding from the same turn's original
  supervision history, never from a different conversation's current selection.
- Honor non-retriable/exhausted supervisor failures. Stop after two consecutive
  failed supervision requests or three structured-format repairs. Successful
  tools and normal long-running goals do not receive a total action-count cap.
- Preserve remote dispatch receipts during cold boot. Reconcile an interrupted
  phone-cloud request to an explicit failure unless an active request or a
  committed inbox result exists. Do not replay tools or silently resend it.
- Persist an interruption-projection checkpoint at the workspace's current
  event sequence so bounded historical checkpoints cannot evict it immediately.
- Acknowledge earlier reply tokens through an indexed read watermark when the
  current conversation's latest page is viewed. Do not decrypt full history,
  acknowledge future entries, or clear another conversation's unread state.

## Verification

- 87 JVM policy, binding, cold-boot, unread, and supervision prompt regressions
  passed, including retention of the recovery marker in a full checkpoint history.
- 24 on-device regression cases passed, including the actual replan boundary,
  cloud/Desktop watchdog isolation, native web research, manual model binding,
  and the existing bounded Codex fallback sequence.
- The original stale unread token cleared after viewing the latest page;
  other conversations' unread tokens remained.
- The original drone request now has FAILED session/workspace state and a
  localized interruption message instead of an orphaned WAITING_RESPONSE.
- A further cold start left its workspace revision and session completion time
  unchanged, retained exactly one interruption checkpoint, and did not recreate
  any read notification tokens.
- Two opt-in public queries used the real phone composer, existing DeepSeek
  credentials, native web tools, and new isolated conversations:

| Query | Final reply latency | Outcome |
| --- | ---: | --- |
| World's smallest drone, with pictures (Chinese) | 93,439 ms | Completed; source links and three Markdown images; first image visually rendered on device |
| Introduction to Zhuhai Lingnan Shijia (Chinese) | 48,824 ms | Completed with cited public sources |

Both live tests verified that all supervision requests remained on DeepSeek.
They did not modify the user's default model or use Desktop execution.
These are single real-network samples, not P95 guarantees or a factual audit of
every statement produced by the model. Search latency still warrants separate
optimization; the evidence supports eliminating the observed recovery loops
and orphaned waits, not a claim that every query now completes in seconds.
