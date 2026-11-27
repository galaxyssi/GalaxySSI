# Android #4620: independent reports on a news event

Android reference: 0092d149fda15f7cb9602232de1bbc8bcc36504c.
iOS implementation base: f6bc5f522b65be056071b56b8b17bd6c54eb4f56 (main).

## Behavior

Group public-news reports only when their original, compatibility-normalized
headlines match, their publisher hosts differ, they share an enabled interest,
and publication dates lie in a 36-hour window anchored to the first report.
Translated headlines, brief titles, questions, missing publication dates and
disabled interests do not establish groups. Intersections apply to the whole
period, so neither time nor topic chains bridge unrelated reports. The separate
life-sciences library is not an input to this public-news grouping.

Highlights selects one deterministic, newest representative per group, then uses
the existing publisher/topic balance. Ungrouped identical headlines are not hidden
by the old same-day duplicate key on this path. All, Unread and Saved retain the
underlying reports and their existing timeline/dwell behavior. Group membership
is computed on a cancellation-aware background task, not per rendered row.

The event button appears in the timeline and Highlights. Its source list retains
each original title, publisher, publication date/time and bounded preview excerpt.
Opening the group does not mark reports read. Selecting a report loads only its
validated original from the archive's own body cache. It neither fetches a missing
body nor invokes a model. The exact selected article is marked read when a cached
body enters the foreground detail view; missing/removed bodies are not marked.
An explicit Original source link remains a user-directed external action.
The obscured timeline cannot accumulate read dwell while the source sheet is open.

An optional readAt timestamp is persisted with the existing article row only on
the first unread-to-read transition. Refresh retains it. Legacy rows decode with
nil and no timestamp is synthesized from collection time, tab visits or launch.
A newer unread report must have been collected after a real recorded read to be
counted as new. Without a baseline, the new count stays zero. A new attributed
sentence is shown only if a previously read report has usable preview text and
the new report supplies a distinct complete sentence. Differing claims remain
separate quotes; this is not semantic synthesis or verification of publishers.
If the cached preview is insufficient, show the count without inventing text.

Preview processing is bounded to 900 characters, four complete sentences of
12 through 220 UTF-16 units, excluding markup, links, multiline fragments and
headline repeats. Existing public-news persistence, original extraction, backlog,
provider policy, translations, speech and conversation transport are unchanged.
No Android/Desktop source, version or API endpoint changes.

## Verification boundaries

Ten synthetic Swift test methods are authored for grouping determinism, bounded
windows/intersections, exclusions, translation/version/negation collisions,
actual read baselines, attributed conflicting accounts, preview filtering,
ungrouped/all/saved retention, refresh/legacy timestamp handling and isolated
persisted source reads. They have not been compiled or executed.

The focused JavaScript source guard checks actual call sites, background
cancellation, exact article reads, project registration, internationalization
keys and unchanged fetch/storage/model-policy files. It does not execute Swift,
UIKit navigation, storage migrations or sentence segmentation. Native rendering,
read-on-display lifecycle and device behavior remain unvalidated.

No native build/typecheck, XCTest, device/provider testing, full repository check,
CI monitoring or IPA. No raw reports, private data or device evidence is uploaded.
This PR is one Android change, not completion of the full iOS parity backlog.
