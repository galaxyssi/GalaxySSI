# Bounded Draft Handback (Android #4659)

Baseline: Android PR #4659, merge `4d6758d60408aa89257b59437a1c2c798cfbf641`.
This increment follows model-authored final editors from Android #4651.

When an editor objects but returns the same draft after Unicode whitespace
normalization, the original synthesis role gets one rewrite and the same editor
gets one recheck. The engine funds both calls before starting either, within the
existing 12-call cap. Eight allocated roles can consume all 12 calls; nine or ten
cannot fund the pair and withhold immediately. No new roles or provider routes
are invented. Receipts still count allocated roles separately from calls.

The writer receives the objective, synthesis brief, actual contributor reports,
rejected draft and validated objection. The editor receives its original
assignment, assigned reports and public objections, plus both drafts and the
objection. Recheck can only accept or withhold; no recursive revision is allowed.
A genuinely changed initial editor correction does not invoke this pair.

Audit, rewrite and recheck JSON undergo bounded duplicate-key preflight before
Foundation decoding, including escaped duplicate keys. Existing plan preflight
limits remain unchanged. Failure, malformed replies and unchanged replacements
preserve the original objection and contributor dissent without publishing the
draft. A valid recheck veto supplies its own reason. Cancellation propagates.
Progress exposes localized stage metadata, not private report contents.

Ten synthetic XCTest methods are authored, not executed. Focused JS checks verify
source contracts and project registration, not Swift compilation, model judgment,
live server acceptance or scientific validity. No native build/test, device run,
CI monitoring, full repository check or IPA generation is performed. No private
or real-device artifacts are included.
