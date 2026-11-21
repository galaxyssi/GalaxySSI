# Android #4304: reference guidance and device movement

Reference: galaxyssi/GalaxySSI#4304, merge
`b2c454a76dccc619f8ca6caae9d3a1f37935d254`.

## iOS mapping

- Show sourced general blood-pressure/resting-heart-rate guidance for adults,
  and age-banded sleep guidance, including infant month bands. Use civil
  Gregorian age at the measurement day in the user's time zone, not today's
  age or a lunar-calendar year count. Unknown/future/unavailable birth dates
  show general adult bands with a disclaimer. Read birth date only under the
  same current local profile-use consent. Never turn this reference guidance
  into a personal target, comparison range, abnormality color or diagnosis.
- Preserve source links and expandable explanations; allow expansion even
  before the first measurement. The base metric list is also visible in the
  first-use state, matching the source PR.
- Add a nullable daily step goal (1...1000000), save/clear validation and
  consent-gated recent-day progress. Do not clamp achievement to 100 percent.
  Separate storage/validation errors and preserve the previous goal on failure.
- Use CMPedometer for opt-in on-device counting. Bind cumulative updates to
  the exact request segment and account, never add the same cumulative count
  twice, preserve a paused total and exclude the paused gap on resume. Roll
  daily windows at local midnight; handle time-zone/clock changes and reboot
  recovery. Display phone-derived steps separately from imported/manual counts;
  do not write them into the measurement archive or apply a saved measurement's
  target/range color to a sensor total. Fall back to saved measurement display
  when there is no phone total for today.
- Use CMMotionActivityManager cycling classification, not a manual timer or
  location-based heuristic. Historical queries and live updates share epoch
  and event-order guards. Count only completed known rides of 30 seconds to
  12 hours, split across local days/DST with daily caps, keep at most eight
  dated totals, and discard uncertain/gap-spanning pending rides. Do not save
  an activity stream, coordinates, route, distance or location samples.
- Wire movement collection at application scope so it is not limited to the
  Health page. Never prompt on ordinary startup/refresh: request Motion &
  Fitness access only from explicit enable controls. Expose denied, restricted,
  unsupported, pending and failed states, with refresh and system-settings
  access. Add the usage purpose to Debug and Release and a bundled Chinese
  InfoPlist localization. No location or new background-mode entitlement.
- Stop updates and invalidate callbacks on suspension/protected-data lock;
  restore through supported historical APIs on reentry. Account changes revoke
  old opt-ins; stale Health screens cannot rebind the global collector. Observed OS
  permission revocation also requires a fresh explicit opt-in. Opt-out stops
  callbacks before storage; durable negative markers prevent later automatic
  restart if writing the protected health file fails.
- Store goals, daily totals, segment/cursor and opt-ins in an owner-bound
  AES-GCM file/key separate from the measurement archive, with complete file
  protection, schema bounds and fail-closed corruption handling. Ordinary
  preferences hold only hashed last-owner routing and negative opt-out flags,
  never goals, birth dates or movement values. No provider/network publication,
  care reconciliation or fabricated saved measurement occurs on sensor updates.

## Platform and evidence boundaries

iOS does not provide the Android foreground service/Google transition receiver
contract. Apple pauses real-time callbacks when suspended and exposes at most
seven days of historical data. This port performs foreground live updates and
history recovery on resume/launch, not a claim of continuous background app
execution. Unavailable history and uncertain classifications are not invented.
Real-world cycling recognition and device accuracy remain unverified.

Added 20 XCTest source methods for age/reference boundaries, progress gates,
cumulative/paused/day/clock/reboot behavior, ride ordering/DST/uncertainty,
encrypted separation/corruption/replay and current profile consent. Tests were
not executed on Windows. Static project checks and grammar comparison cannot
prove Xcode compilation, permission dialogs, physical sensors, UI screenshots,
background/kill/relaunch behavior or battery impact. No IPA is included.

## Sources Reviewed

- [Apple pedometer updates](https://developer.apple.com/documentation/coremotion/cmpedometer/startupdates(from:withhandler:))
- [Apple pedometer history](https://developer.apple.com/documentation/coremotion/cmpedometer/querypedometerdata(from:to:withhandler:))
- [Apple activity updates](https://developer.apple.com/documentation/coremotion/cmmotionactivitymanager/startactivityupdates(to:withhandler:))
- [Apple activity history](https://developer.apple.com/documentation/coremotion/cmmotionactivitymanager/queryactivitystarting(from:to:to:withhandler:))
- [CDC sleep reference](https://www.cdc.gov/sleep/about/)
- [AHA resting pulse reference](https://www.heart.org/en/health-topics/high-blood-pressure/the-facts-about-high-blood-pressure/all-about-heart-rate-pulse)
- [2025 Chinese primary-care hypertension guideline](https://cs.medjournals.cn/article/doi/full/10.3760/cma.j.cn112148-20250401-00234)

Android version metadata, Desktop, CI and later Android PRs are not changed.
