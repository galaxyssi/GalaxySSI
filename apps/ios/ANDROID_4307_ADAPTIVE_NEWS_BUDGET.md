# Android #4307: adaptive Following news budget

Reference: https://github.com/galaxyssi/GalaxySSI/pull/4307

Android merge: `7b0efce101f7900ee243ccb160941f6a51ec0c1d`.

## Policy and persistence

- No reading in the previous 24 hours: twelve-hour completed feed sweeps, even
  while charging. Recent readers: thirty minutes charging, one hour on battery.
- Inter-batch feed spacing: 15 seconds charging, 60 seconds active on battery,
  five minutes idle on battery. Partial scans keep the next unvisited source;
  only completed sweeps acquire the long interval.
- Article batches: 10 articles / 60 seconds charging; four / 30 seconds active on
  battery; two / 30 seconds idle on battery. Network parallelism is two charging,
  one on battery. Idle publisher probes are not started on battery.
- Article cooldown after output: two minutes charging, fifteen minutes active on
  battery. Zero output: ten minutes charging, forty-five minutes active on battery.
  Idle on battery: twelve hours regardless of output.
- Reading activity, feed/sweep timestamps and article output boundaries survive
  restarts in dedicated news-only defaults. The article timestamp and output flag
  are one stored value, written before a batch and at its final boundary.
- Learned feeds save their last successful poll and scheduled interval. Reading
  or power changes reschedule successful cadence without replacing failure backoff.
  Optional fields preserve decoding of older publisher archives.

## CPU and checkpoints

`getrusage(RUSAGE_SELF)` provides summed user/system process CPU seconds. A window
at least ten and at most sixty seconds using at least ten percent of one core
defers discretionary news for five minutes. Long idle gaps and counter resets
start a new sample rather than charging old work to the next batch. Existing
battery/low-power/thermal gates still apply; unknown CPU sampling defers news.

Feed results and source cursor positions are saved after each bounded source.
Body extraction checkpoints and completed translated segments remain stored when
the budget yields; unprocessed claims are released without retry penalties.
Automatic headline translation and optional source review also check news pressure.
The backlog resumes deferred batches while its screen remains active and stops
when closed/backgrounded. Interactive reader translation is not placed under the
discretionary batch cooldown.

## Live feed and iOS lifecycle

The news SSE stream is eligible only while charging and recently reading. A
five-second watcher cancels the stream when power/CPU eligibility changes, even
without incoming events. In-flight story completion is rechecked before storing;
pending IDs survive pauses. Reading/list/search entry updates the activity stamp.
Foreground feed polling reevaluates reading, charging and CPU conditions rather
than keeping a fixed fifteen-minute interval.

This is an iOS foreground implementation, not an Android WorkManager service.
SwiftUI task cancellation stops collection when the scene is inactive; the archive
and budget resume it on reentry. Resource checks occur at bounded feed/network,
extraction and segment boundaries, not by forcibly interrupting an executing
native model or DOM parser. No background entitlement, chat/transport/health gate,
Android/Desktop code, app version or IPA change is introduced.

Apple platform references:
- https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/getrusage.2.html
- https://developer.apple.com/documentation/uikit/uidevice/isbatterymonitoringenabled
- https://developer.apple.com/documentation/uikit/uidevice/batterystate-swift.property

## Verification scope

Added regression XCTest source for profile boundaries, persistence and power/read
rescheduling, CPU thresholds/cooldown/idle/reset, partial feed cursors, learned-feed
backoff and legacy decoding, claim release, and saved translation preservation.
Tests are not executed in this task. Only targeted structure, whitespace and Swift
grammar checks run on Windows; no Xcode build, iPhone power measurements or runtime
SSE cancellation verification is claimed.
