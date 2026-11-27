# Owned observation job lifecycle

Independent main-based Android #3119 follow-up. Base:
`c6bad3465c673dfb2dcecb23b095185c129c7447`.

Android's `MainActivityAgentExecution.cancelConnectorTimeouts` cancels registered
callbacks for an original source. iOS already had active owned Desktop observation
wakes. However, it removed a job from its registry before awaiting the recovery
sweep. Background clearing or a replacement wake could no longer cancel that
in-flight job, which could later schedule another old wake.

## Production changes

- Retain the job and token throughout the existing asynchronous recovery query.
  Revalidate the exact token before observing and after the suspension, before
  removing or rescheduling anything. A replaced job cannot remove its successor.
- Retain profile identity alongside each job. Reconciliation cancels old-profile
  jobs; paused/plan-only/observe-only/inactive restoration cancels active jobs.
- Background, protected-data loss and runtime plaintext-clear notifications
  cancel jobs and clear their wake clocks. Foreground reentry runs the existing
  durable waiting-connector restoration with its existing policy checks.
- Successful durable user cancellation clears observations for the task's saved
  pending connector actions. A committed settled native connector clears only
  its exact owner/source/profile observation before normal continuation.
- Existing 200-job admission, stage clocks, query throttles, exact managed owner
  checks, Desktop recovery queries and terminal continuation policies remain.

## Source verification

`node apps/ios/tools/check-observation-job-lifecycle-scope.cjs` pins the exact
approved lifecycle/worker sections and compares all other coordinator source with
main after exact independent pending-PR hooks. Eight negative source mutations
check ownership, removal order, profile, lifecycle, restoration, cancellation and
terminal cleanup hooks. Native timing/transport/failure policy files are frozen.

These are source contracts, not executed Swift scheduling or concurrency tests.
No Swift/native build, XCTest, full repository check, CI inspection, live network,
simulator/device execution, IPA or private evidence upload is included.

Local integration with the thirteen pending branches (#4664 and #4671-#4682)
had no text conflict. All nineteen focused source guards, `npm run check:ios`
and `git diff --check` passed on the combined tree. The pairing-history guard
recognizes only this exact independent lifecycle delta through its exported
normalizer. It adds no lifecycle feature code or blanket assertion exception.

The historical `check-active-native-observation-scope.cjs` still fails its old
whole-Services snapshot comparison. Applying that guard's retained projection
to unchanged main reproduces the exact same Services mismatch; this change's
normalized projection equals that main projection. Original assertions remain,
and the full historical guard is not reported as passing.

## Limits

Cancellation stops the observation task, not an already sent external operation.
An already entered shared recovery sweep is not guaranteed to stop immediately;
its existing managed identity and publication checks remain authoritative.
Notification handling is dispatched onto MainActor, not a synchronous zero-delay
privacy-erasure guarantee. No new OS background execution is granted.

This does not synthesize remote failure, invoke the generic timeout resolver,
release a remote run slot, replay an effect, cancel a provider or discover a new
fallback candidate. Generic timeout/deferred discovery and full Android parity
remain incomplete. No native, restart, race or performance acceptance is claimed.
