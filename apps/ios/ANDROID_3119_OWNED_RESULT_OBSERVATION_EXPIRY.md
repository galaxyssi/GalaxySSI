# Owned result observation expiry

Independent #3119 recovery follow-up, based on main
`c6bad3465c673dfb2dcecb23b095185c129c7447`. The reference is the current Android
`AndroidAgentRemoteSilence` result-delivery expiry path, not a claim that every
current recovery policy originated in #3119.

## Production connection

Both legacy and journal managed recovery call the same owned-native observation
preservation path. Previously its single overdue flag could prevent a later
terminal-result-delivery warning, and the task could remain indefinitely shown
as waiting after the existing fifteen-minute terminal delivery window expired.

- Pass the actual current recovery record and clock into that shared path.
- Preserve exact managed source/owner/agent/contact/conversation/turn/task/
  generation binding, existing expiry clocks, current profile/route and the
  original waiting action and receipt. Recheck the current recovery and managed
  rows before any task commit, together with current session/privacy/cancellation.
- Deduplicate by expiry reason plus observed stage clocks, not one forever-set
  boolean. An ordinary status warning can therefore escalate to a missing-result
  warning after the existing terminal delivery deadline.
- Ordinary status silence remains a waiting observation, not a failed task or
  retry grant. A proved terminal status with an undelivered result is committed
  as blocked/unverified using the existing unknown-dispatch continuation flags.
  The pending request/result owner stays queryable, with automatic retry denied.
- Once native ownership is recognized, deferred/failed presentation updates
  still return preservation rather than causing the caller to synthesize an
  ordinary remote failure. A failed task commit is retried by later observations.
- Existing late committed-success settlement clears those uncertainty flags
  and resumes the original waiting continuation. Its implementation is unchanged.

No external request is cancelled, redispatched, rerouted or declared successful.
No remote failure is inferred from elapsed time. No run slot or managed owner is
retired by this change. Existing keys provide the localized result/status notices.

## Verification limits

The focused source guard pins the exact helper and shared preservation method,
compares coordinator source outside that method and two caller hooks with main
after exact independent pending-feature normalization, rejects five boundary
mutations and freezes the timing, receipt/settlement and transport kernels.

Eight XCTest methods are authored, not executed: ordinary expiry, terminal result
expiry, prior-stage escalation/duplicate suppression, premature/unproved terminal
rejection, pending identity mismatch, foreign/settled owner rejection, late success
settlement and manual/routing lock retention. These are fixture sources, not
executed persistence, scheduler, MQTT or device acceptance.

No Swift/native build, XCTest execution, full repository check, CI inspection,
live model/network, simulator/device run, IPA or private evidence is included.

Local integration with seventeen pending branches (#4664 and #4671-#4686) had
no textual or Xcode registration conflict. All twenty-three focused source guards,
`npm run check:ios` and `git diff --check` passed on that combined tree. The
pairing-history and observation-job guards in #4664/#4683 compose only this exact
independent method/caller delta through its exported normalizer. No feature code
is duplicated there and no original assertion is removed. No remote PR is approved
or merged by this verification.

## Remaining work

This is not automatic model liveness assessment, remote-silence replay or generic
timeout/fallback/deferred-candidate completion. Protected/private/paused/changed
owners can defer presentation. The shared recovery sweep, not an OS background
execution guarantee, determines when expiry is noticed. Initial native ownership
lookup behavior outside the recognized-owner branch is unchanged.

The existing uncertainty settlement only clears replay barriers for a verified
successful completed response; a late failure retains the conservative barriers.
Full Android parity, native concurrency/fault/restart and privacy acceptance remain
incomplete. No broad completion claim is made.
