# Android #4614: scoped atlas discussions and chapter return

Android merge: 8b7f1c7512b560ad378ce8793e632de430360246.
iOS base: 4c876a62035990a70a69a453edf2503408d96911 (main).

## Implemented changes

The atlas confirmation panel accepts an optional reviewed question, limited to
500 UTF-16 units without splitting characters. It appends that question to the
frozen educational prompt only after confirmation. The full request is bounded
to 9,000 UTF-16 units and 32,000 UTF-8 bytes; oversized contexts fail visibly
rather than silently dropping the displayed chapter or the user's question.
All new English/Chinese copy lives in existing atlas resource tables.

Reuse is keyed by body-atlas:<catalogue object ID>, never by translated titles.
An encrypted, identity-bound index points to exact persisted conversation IDs.
Only active, Agent-created, non-private, non-paused, unmerged sessions with the
same topic qualify. Rename does not break reuse; archived/private/paused/deleted,
merged, foreign-topic or foreign-owner entries do not qualify. A new session is
not dispatched until both its existing encrypted metadata and the encrypted index
are saved. Index authentication/decode failure fails closed, rather than creating
another conversation on every tap. The bounded index is destroyed during the
existing full data reset. Legacy broad body-atlas conversations are not adopted
by title or guessed ownership.

Structure questions include the selected landmark/overview caption and step from
the same ordered plate landmarks used by the UI. Nested lessons use the artwork
view actually displayed. Existing function context already includes the exact
selected course/chapter, caption, teaching scope and references; its live-phase
snapshot is retained. The whole-body entry no longer substitutes the highlighted
organ as the discussion owner. Values remains excluded from this public-prompt
path; personal health records and the separately authorized health discussion
pipeline are not read or changed.

The existing synchronous playback pause happens before taking the question
snapshot. Native chapter clocks/player behavior is unchanged. Enter the existing
Agent page only after the confirmation sheet has dismissed, not after a guessed
delay. Preserve native Back for this atlas entry while leaving ordinary home
navigation unchanged. Returning restores the captured detail/research/model
scroll offset; chapter, structure-step and artwork state remain in the retained
atlas. Restore the previous main Agent conversation only when the original
identity/plaintext generation and exact current discussion still match. Do not
override a newer explicit conversation choice or recreate a deleted owner.

The existing bounded in-process capability remains single-use, identity/session
bound and expiring. Recheck protected-data access, identity, generation and
session eligibility before navigation, then recheck exact topic/session flags
before handing off and immediately before send. No URLs, external extras or
composer attachments can create an educational handoff. Failed sends can recover
as a draft, not by replaying the capability. This pushes an Agent view, not the
application launcher/root, and introduces no notification-permission request.
Actual permission-popup/native navigation behavior is not device-validated.

## Verification boundaries

Ten synthetic Swift methods are authored for topic identity, rename/reuse,
ineligible/deleted sessions, encrypted index reopen/corruption, foreign owners,
question bounds, visible structure steps, live function chapters and whole-body
ownership. They have not been compiled or executed. Existing one-use capability,
function context and clock fixtures remain in place. No actual Back, gesture,
permission, rendering, lifecycle or model adherence result is claimed.

The focused JavaScript source contracts inspect production hooks and compare
the unchanged public/Values prompt body, personal-health path, clocks, encrypted
store implementation and root launch code against main. The function-context
guard follows the new questionSnapshot wrapper through to the original live
functionSnapshot, rather than checking an obsolete direct-call spelling.

No Swift/native build/tests, live network/model, device acceptance, CI monitoring,
full repository check or IPA. No raw reports, private evidence or screenshots are
uploaded. Android/Desktop sources and versions and the iOS 15 minimum are unchanged.
This is one Android PR port, not completion of the entire backlog.
