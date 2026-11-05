# Android health analysis profile context

Health Assistant starts with no profile context selected. A user can opt in
to any of four saved basic fields for a foreground analysis: birth date,
reference sex, height, and physiological context. Name, unsaved drafts, and
unselected fields are not read by the analysis. Self-reported values are
displayed separately from confirmed measurements and do not change their
statistics. An unfilled selected field remains visibly missing.

The encrypted profile store records a version stamp for only the selected
fields and the profile generation. An edit or removal of selected context
invalidates the displayed result and any in-flight online explanation. An
unrelated committed edit does not invalidate a displayed result. Analysis
requires the existing profile privacy permission and logs selected field
names, not their values. Going to the background clears the result and
selection. The cloud payload remains measurement aggregates only.

The separate background picker allows explicit selection of saved history,
medication and allergy entries. It loads one 30-entry page at a time, retains
choices across pages and categories, and includes a selected-only view for
removing obsolete choices. At most 30 entries can be included in one analysis;
this does not limit the number of saved entries. Cancel discards picker edits.
Only the selected entry revisions are captured. A changed or deleted entry
cannot silently substitute a newer value, even before the first analysis.
The audit records the entry count, not names, IDs or details.

The device suite uses isolated databases and synthetic fields. Its online
exchange is a fixture and does not send health information to a real provider.

On Tab Active3 (SM-T575) with 0.1.7.63, 12 assistant tests and 68 profile,
privacy, overview, and weekly-report regressions passed without skips.
On 0.1.7.64, all 16 assistant tests and the same 68 related regressions
passed without skips, including cross-page selection and cancellation,
selected-entry deletion, and the unchanged measurement-only payload.
