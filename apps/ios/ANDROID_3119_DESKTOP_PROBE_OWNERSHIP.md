# Desktop recovery probe ownership

Follow-up to Android #3119 on main 104e4e156ed187a8e5980813efc901bb08d2bd34.

## Production defect

The shared foreground Desktop recovery sweep also runs with journal transport.
Its ordinary, UUID-source branch called the legacy recovery request with
`online: false` when the legacy client was disconnected. That call is not a
read-only availability check: the recovery kernel persists `lastProbeAt`,
increments `misses` and may open/reset the probe window BEFORE checking online.
The journal pump shares that same recovery state and rate limit. The unrelated
offline legacy caller could therefore consume a journal probe interval and
record a missed observation despite not attempting to send a journal query.
No device reproduction or deterministic complete query starvation is claimed.

## Change

Require legacy transport ownership immediately before this ordinary probe path.
In journal mode only the existing journal pump may claim that probe clock.
Its exact destination, route readiness, revocation, identity, wire validation
and publication checks are unchanged. Legacy mode retains its prior offline
accounting, probe intervals and online queries. No wire format or outbox changes.

The gate is after existing accepted/assembled-result handling and Codex replay
dispatch. It does not disable either path. Managed/team/goal-work recovery,
query expiry, terminal projection, fallback, retry budgets and cancellation
are unchanged. In particular this does NOT implement generic active timeout
observation, local/cloud status querying, or complete Android #3119 parity.

## Verification

`node apps/ios/tools/check-desktop-probe-owner-scope.cjs` checks the exact live
caller gate, the existing offline mutation order, the journal query path and
whole coordinator equality outside this gate against the stated main baseline.
Recovery/transport/timing kernels remain exact. Earlier scope assertions are
retained with only this declared hook normalized.

Source checks are not Swift compilation or runtime evidence. No native build,
XCTest, network/device/restart acceptance, CI watching or IPA is performed.
