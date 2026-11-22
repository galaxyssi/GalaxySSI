# Android #4320: compact result selector and partial refresh

Source: https://github.com/galaxyssi/GalaxySSI/pull/4320

Android merge inspected: `48ce7fc9b22cbc15f4a1c406582c5e6d8ed40b3c`.
Independent follow-up to the main-based sampling/list work (#4421/#4423).
This change does not include Android #4318/#4319 theme/profile changes.

- The selector's background hugs its label, with a 48-point minimum target,
  bounded width (60% of the available row, at most 180 points), single-line
  truncation, and the full localized label available to accessibility/tooltips.
- Period selection is local to the measurement view. Remove the parent period
  binding, UUID view replacement and parent reload from picker callbacks.
  Activity tiles, shortcuts, footer and the existing scroll container are not
  replaced when the result period changes.
- A separate cancellable query prepares the new measurement projection while
  keeping the displayed snapshot. Disable result navigation/filter/expansion
  until it succeeds. Adoption revalidates the exact archive/owner/consent/source
  snapshot; success resets expansion only after publication.
- Reselecting a displayed/pending period is a no-op. Selecting the displayed
  period during a different pending request cancels the latter without another
  query. Failures roll back to the displayed selection and report the error;
  stale displayed data is reloaded rather than retained silently.
- Pure request identities prevent superseded results from committing. Picker
  callbacks also require the exact active sheet identity, scene and owner.
  Published-value adoption is deferred past the property setter, avoiding reads
  of its old value during Combine's willSet delivery.
- Backgrounding, protected-data loss and owner changes clear pending/display
  snapshots and picker state. Returning from a pushed detail keeps its source
  NavigationLink alive but revalidates data; hidden sources start no new query.
  Consent revocation resets the period and removes protected summaries.

Focused XCTest source covers same-selection no-ops, rollback, supersession,
reselecting the displayed value, and nullable Latest selection. Existing source
snapshot/cancellation tests remain. No tests executed, as requested.

Static checks only: project structure, Swift grammar and git diff whitespace.
No Swift type checking, Xcode build, simulator/device UI tests, screenshots or
IPA on Windows. Intrinsic selector layout, sheet gestures and scroll continuity
still need native validation. No data migrations or Android/Desktop changes.
