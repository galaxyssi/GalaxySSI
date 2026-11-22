# Android #4316: include today in activity comparisons

Source: https://github.com/galaxyssi/GalaxySSI/pull/4316

Android merge inspected: `c73a4e01324d5676c93953968d8788e7f062c154`.
This independent iOS change starts at main after #4419 (Android #4314); it does
not include the sampling-period UI changes in iOS #4421 (Android #4315).

## Mapping

- `GalaxySSIHealthActivityComparison.trailing` includes today in every 7/30/90-day
  preset using local calendar arithmetic, not fixed-second windows. Custom ranges
  may end today, may cover 1-366 days, and cannot extend into the future.
- `today` distinguishes absent/unobserved values from genuinely observed zero.
  Current-day observed steps, paused nonzero totals and completed cycling remain
  visible. Ongoing cycling includes only confirmed duration, with earlier rides
  counted once. It does not extrapolate to wall-clock now.
- `withDay` overlays only the selected current-period date and retains the
  archived floor and previous-period values. Each update starts from the cached
  history query, allowing provisional cycling contributions to be corrected down.
- `checkpoints` now archives completed cycling days only. It no longer settles
  a copy of an active ride into durable history. Previously saved history is
  preserved; this does not delete or rewrite any records.
- `GalaxySSIHealthRecords.motionChanged` supplies the persisted motion value
  snapshot. The comparison page coalesces foreground events for 750 ms and
  updates the cached projection without a new history/database query per event.
  Owner checks remain mandatory; other notification consumers ignore the new
  payload. Missing legacy payloads trigger a normal reload.
- Date ranges, prior-period summaries, bottom legend and explanatory footer are
  removed from the compact page. The chart has no date labels; tapping it opens
  accessible current/previous dated values. Unknown totals show a dash, not zero.
  The chart retains gaps, zero points and a minimum three-unit vertical scale.
- Day-change, significant-clock-change and time-zone events refresh the query.
  Backgrounding, locking, account changes and navigation away cancel work and
  clear cached decrypted comparison/motion values. Query publication rechecks
  summary consent and its event identity. New labels are localized.

## Verification and limitations

Focused XCTest source covers presets across DST/year/leap boundaries, future
range rejection, unknown/zero steps, overlays, monotonic archived floors, cycling
corrections, cross-midnight contributions and non-persistence of active rides.
No tests executed, per request.

Static checks: `npm run check:ios`, modified Swift grammar parsing and
`git diff --check`. These do not establish Swift type correctness or native
rendering. No Xcode build, simulator, device run, UI screenshot or IPA on Windows.
No Android/Desktop changes, app version bump or generated binaries.
