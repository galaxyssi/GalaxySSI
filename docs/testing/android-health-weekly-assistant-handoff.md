# Android health assistant weekly-report handoff

Opening a weekly report from Health Assistant passes only the selected end
date, time zone, metric set, comparison setting and observation-version
stamp. The report and export options use those defaults. Self-reported
profile values, model output and individual measurements are not in the
handoff. Including records in a PDF still requires a separate selection,
preview and explicit save consent.

The linked report uses the original observation versions. An edit does
not silently replace a linked analysis. The user can review an updated
report using the same scope, choose a different week, or return to the
assistant. Export preview checks the versions of selected overlapping
metrics before proceeding. Contributor links open the exact stored record
revision in the linked date window.

Device tests use isolated synthetic data and exercise a historical week
through the real assistant action, the report-to-record revision route,
stale recreation, and an edit made while export options are open.

On Tab Active3 (SM-T575), 54 focused instrumentation tests passed on
0.1.7.70, including all three handoff cases, weekly report UI and store,
assistant, overview, trend point navigation, and privacy store tests.
