# Android #4624: preserve the active reading position

Android reference: d9b79519d74328de6df507b898372d8f4ba359cf.
iOS implementation base: 20bb51f10021351bd4ea62ae1fc37e9ed65e5752 (main).

## Chat behavior

Use owner/conversation-scoped, in-memory identity/time/classification snapshots to
recognize a genuinely new reply, including an in-flight turn completed behind a
newer unrelated message and an equal-timestamp append. Initial history hydration,
ordinary metadata edits, another body/stream replacement for a replied turn,
older prepends, approval/control, waiting, failed, user and system rows do not
create a new-reply signal. Snapshots do not retain message prose or rich payloads.
Health's separate encrypted transcript contributes actual answer IDs rather than
every progress/permission revision. Its initial mount does not signal an arrival.

Keep the existing Agent jump-to-latest action and add the same small action to peer
chat. Merely browsing away from the bottom no longer creates an arrival badge.
Waiting/ASR progress does not force a reader away from older text. An explicit
latest action enables following again; genuine bottom contact during user
scrolling clears the signal. Tighten bottom contact from 56 points to one point,
and do not infer user follow intent from a media/viewport resize. System notices
retain their non-following behavior. No composer or header redesign.

A native idle-only display probe retains the first visible selectable paragraph
through late media layout. When no native paragraph is available, it retains a
stable message-row marker. It adjusts scroll offset by the target's observed
layout displacement, including a target pushed outside the viewport, while
clamping to legal content bounds. This is geometry anchoring, not pixel tracking.
It cannot preserve a text line if the paragraph's own content/font/width is
replaced; explicit history/initial-position operations retain their existing
row-based paths. The bounded scan skips nested scroll/web containers and does not
add gestures, change text selection or interfere with paragraph speech callbacks.

User dragging/deceleration, an intervening scroll, explicit epoch/scope change,
background/lock/privacy clearing or view teardown wins over the anchor. The probe
holds weak native targets and invalidates its display link on detach/dismantle.
Following readers stay at the latest tail during layout growth. No chat transport,
history authority, tool execution or local/cloud model behavior changes.

## Health filters

Capture a live metric-row offset before abnormal filtering, expansion/collapse
and committing a successfully staged week/month selection. Retain exact metric
and unit/condition/side identity first; if it disappears, choose the nearest
surviving metric, preferring the following neighbor on equal distance. If no old
metric survives, return to the filter heading instead of the page top. Missing
rows and changed dimensions remain distinct marker keys. Restore only while the
owner/screen is active and protected data is available, and only if the user has
not scrolled since capture (allowing the ordinary shrink clamp). Privacy clearing,
failed adoption and disappearance discard pending anchors. Markers are local
geometry only, with no persistent reading history or measurement values.

## Verification boundaries

Ten synthetic Swift methods are authored for first/repeated replies, late open
turns, equal timestamps, old history, ownership/hydration fences, production row
classification, text-free snapshots and nearest surviving metric order/bounds.
They have not been compiled or executed. Native display-link lifetime, keyboard,
media reflow, filter layout, selection/speech gestures and manual scrolling need
real iOS validation; source checks do not certify those behaviors.

No Swift build/typecheck, XCTest, native/device/provider tests, CI monitoring,
full repository check or IPA. No private data, screenshots or raw device evidence
uploaded. Android/Desktop sources and versions are unchanged. This is one parity
change, not completion of the remaining Android-to-iOS backlog.
