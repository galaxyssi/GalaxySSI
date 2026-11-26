# Android #3119: live adapter-health routing

Reference: Android `e7c6af6ef3eed21c7fb697b4458d1cf742833dc4`,
`AgentResourceRouter.kt` health, reliability and observed latency scoring.
Actual source baseline: `5f63d903558458025c872851369dbfd557c75cf1`, after
#4574 attribute weights and #4575 paired/domain ordering merged. This increment
does not repeat those merged implementations.

## Actual Data And Callers

The existing persistent `AgentProviderHealthLedger` already records adapter
operations. The coordinator now injects the same ledger into the native control
plane and Auto routing; the default persistence backend is unchanged.
`AgentRoutingHealthSnapshot.capture` reads its actual snapshots once per capture,
using the exact registration's runtime, target and cloud-provider scope IDs.
It does not infer an installation from a family alias or display name. Duplicate
exact registration IDs use the first entry, matching existing admission lookup.

Main Auto selection, native preparation refresh and fresh failure reselection
receive a fresh health snapshot. Initial automatic admission also excludes
blocked runtime/provider scopes. The selector checks health before its healthy
stable-primary shortcut and before building its baseline decision; an open
preferred endpoint cannot win because it was remembered. Missing health remains
unknown and adds neither fabricated samples nor default reliability points.

Same-Desktop recovery rankings now consume both actual paired presence and the
fresh snapshot while retaining the original exact eligible-ID set, confirmed
failure recognition, retry budget, disclosure, identity and replay constraints.
No different Desktop/cloud candidate is added to that recovery path.

Observed target reliability contributes its actual percentage; observed runtime
or cloud-domain reliability contributes half. Target observed latency takes
precedence over provider EWMA, with Android's fast/normal divisors and bounded
penalties. Domain latency has its separate bounded penalty. Zero-sample records
do not contribute latency or reliability. Percentage calculation does not
multiply untrusted integer counters and handles large counters without overflow.

## Read-only Admission And Existing Authority

Selection never calls acquire, records a success, clears a circuit, reserves a
slot or starts a probe. The existing heartbeat/readiness predicate is extracted
into one pure policy shared with the original ledger observer. A read-only
projection can therefore admit a readiness-eligible half-open candidate without
changing persisted state; actual adapter acquisition still owns its probe lease.
An active half-open runtime lease blocks another selection. Authorization and
protocol failures cannot be cleared by an unrelated heartbeat.

Cloud provider recovery uses the existing configuration-recovery predicate.
The actual ledger write/acquire path remains authoritative and unchanged.
The existing iOS failure thresholds, cooldowns, health persistence, transport
attribution, cancellation exclusions and operation semantics are retained, not
replaced by the older Android store's thresholds. There is no new health store,
network protocol, replay, timeout failure, data disclosure or execution grant.
Admission and ranking captures are separate reads, not an atomic reservation.

## Limits And Remaining Work

These are adapter-operation measurements: existing connect/status/queue-receipt
samples are not task-completion evidence, model answer quality or end-to-end
latency. This change does not fill missing asynchronous completion producers or
reinterpret an acknowledgement as success of the user's task. Runtime-family
and cloud-provider scopes are not a new physical Desktop-wide transport circuit.
No record is created when a scope lacks observations.

Full Android resource/domain health parity, complete observed token/cost usage,
earlier pre-shadow limiting, generic timeout/deferred observation, broader
attachment/rich-output and resumed-provider parity remain incomplete. The
independent empty-plan factory is not an active automatic coordinator entry with
connector targets; no unused serialized pairing field was added merely to make
that helper appear integrated. This is not completion of #3119 or all Android PRs.

Eight Swift fixture methods were authored, not executed: real-ledger read-only
capture, exact installation scope, shared readiness/lease rules, stale/future
heartbeats, authorization protection, cloud configuration recovery, real-sample
latency precedence, and actual selector/replay containment. Native compilation,
typecheck, XCTest, device/network/restart acceptance, CI monitoring and IPA
generation were not performed.

The new source check freezes complete production files outside declared hooks,
including the original adapter/response/timeout/budget/plan kernels. Existing
scope checkers compose those hooks before historical comparisons. Their success
is source evidence only, not runtime acceptance. The old stable-auto whole check
still has preexisting manual-selection baseline differences.

Passed for this increment: the new health source scope, existing provider-ranking
and observation-timing scopes, six context/knowledge-gap/autonomous/research/
background/live-planning source scopes, changed JavaScript syntax,
`npm run check:ios` and `git diff --check`. The old stable-auto check was rerun
and still stops at the preexisting `GalaxySSIAgentModelSelectionView.swift`
baseline mismatch; no whole-check success is claimed.

```sh
node apps/ios/tools/check-routing-health-scope.cjs
```
