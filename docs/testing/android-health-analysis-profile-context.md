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

The device suite uses isolated databases and synthetic fields. Its online
exchange is a fixture and does not send health information to a real provider.
History, medication, and allergy entries are not part of this basic-field
selector.

On Tab Active3 (SM-T575) with 0.1.7.63, 12 assistant tests and 68 profile,
privacy, overview, and weekly-report regressions passed without skips.
