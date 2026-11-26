# Android #3119: provider resource ranking attributes

Android reference: `e7c6af6ef3eed21c7fb697b4458d1cf742833dc4`,
`AgentResourceRouter.kt`, resource score calculations. The current Android router
at source baseline `cb3f7c6aadf6884b7fd9fb76d8bdf0a151f507cb` retains these
weights and uses the same inferred/declared capability policy as iOS.
The updated source-check baseline is `ab1df6efb94ebbf7bffa19e86859a4e6dd4bd3cf`,
after observation timing PR #4573 merged. Those merged changes are not this PR's diff.

## Production Connection

The existing `AgentQualityRoutingService.baselineDecision` now calls the new
`AgentProviderResourceRanking` for each candidate surviving its existing
mandatory-capability filter. `AgentConnectorRouteSelector` already consumes
these candidate scores in its actual calibrated candidate ordering. This is
not a standalone unused score model. The new source file is in the app target.

The default snapshot reads the existing thread-safe network detector once for
availability, validation and metering. Callers can supply an explicit environment.
That environment is retained in the returned decision. No additional monitor,
network request or permission is created.
An explicitly supplied environment bypasses the detector read entirely.

Weights now match Android for quality/complexity, fast latency, economy cost,
confidential-data trust preference, background support, metered cloud and
unvalidated network penalties, context shortfall, long paid input, non-cloud,
live-tool support, private phone, fast/economy/frontier bonuses. Existing provider
performance supplies bounded failure-rate and latency penalties when attempts
exist; non-finite telemetry cannot trap during Double-to-Int conversion.

Android's resource-family preference order is now applied too, including its
code/knowledge, live, fast, economy, quality and private variants and 180/130/90/50/20
bonuses. Main Auto selection, native preparation refresh and fresh failure
reselection pass actual `store.serverLinks` paired presence. This boolean means
that a paired Desktop exists, not that any particular target is authenticated.
Callers without that snapshot default to false; no pairing is inferred from a
display label, family alias or catalog trust default. Family canonicalization
only computes the bonus; candidate IDs and registration identities stay exact.

The actual selected decision now publishes at most six unique nonblank alternate
target IDs. A trusted-Desktop primary prefers cloud/phone alternatives, then a
different Desktop/private failure domain, then the same domain. Within a tier,
the existing calibrated order is preserved, not re-sorted by uncalibrated scores.
Other primary locations keep their calibrated order. No catalog-only candidate
is introduced. The existing fallback-tier policy itself is reused unchanged.

## Preserved Boundaries

Healthy remembered/displayed primaries still return through the existing
single-target fast path without ranking alternatives. Attribute weights do not
override that stable-primary behavior. When ranking is needed, the existing
quality/self-calibration stages still follow the baseline score.

The existing exact registration/capacity/privacy/network/provider admission,
manual selected target and locks, fallback authority, effect ownership and
transport publication are retained. The selector's alternate metadata list is
now bounded and domain-ordered; it does not grant permission to execute it.
Scoring does not authenticate a provider or authorize disclosure.
Inferred capabilities remain soft preferences and explicit mandatory capabilities
retain their hard filter. No old token/cost/memory/battery hard budget cutoff is
reintroduced; the current telemetry-only counter policy is preserved.

## Remaining Work And Evidence

This is not the full Android router: persisted resource/domain health circuits,
health latency precedence, complete observed token/cost usage ingestion and
the generic timeout/deferred-observation workflow remain incomplete. Android's
earlier pre-shadow six-candidate reduction is not reproduced: iOS still observes
its existing candidate set for quality/self-calibration before bounding the
published alternatives. Paired presence is not yet plumbed into every independent
planning or same-Desktop replay helper. No default
healthy samples, fake usage or synthetic circuit state are inserted to mask
those missing inputs. This increment must not be reported as #3119 completion.

Eleven native fixture methods were authored, not executed. They cover exact weights,
network/context preferences, finite telemetry, capability-source semantics and
actual selector/stable-primary consumption, family bonuses without identity or
trust mutation, explicit paired input, domain ordering, deduplication and the
six-alternative boundary without catalog resurrection. The JavaScript scope check and
project structure check are source evidence only, not Swift type correctness,
XCTest, native/device delivery, routing acceptance, performance or privacy proof.
No native build, CI monitoring or IPA was performed for this increment.

The historical `check-stable-auto-admission-scope.cjs` composes the exact ranking
hook normalizer for its old quality-source comparison. Its full execution still
fails on preexisting manual model-selection changes since its older
`ddcb2a69acd02ea12d20fb469e779d4d87b85a4f` baseline, not on this ranking hook.
The new check instead freezes current registration/admission, task-budget,
provider-profile, self-model and executor sources at the stated current baseline,
and the complete selector/services outside the explicit paired argument and
fallback-projection hooks.
No historical whole-check success is claimed.

The observation timing source check and the six context/knowledge-gap/autonomous/
research/background/live-planning source contracts passed after composing those
exact hooks and the four new app-target file references. These are not native tests.

```sh
node apps/ios/tools/check-provider-resource-ranking-scope.cjs
```
