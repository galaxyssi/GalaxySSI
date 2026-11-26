# Android #3119: provider resource ranking attributes

Android reference: `e7c6af6ef3eed21c7fb697b4458d1cf742833dc4`,
`AgentResourceRouter.kt`, resource score calculations. The current Android router
at source baseline `cb3f7c6aadf6884b7fd9fb76d8bdf0a151f507cb` retains these
weights and uses the same inferred/declared capability policy as iOS.

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

## Preserved Boundaries

Healthy remembered/displayed primaries still return through the existing
single-target fast path without ranking alternatives. Attribute weights do not
override that stable-primary behavior. When ranking is needed, the existing
quality/self-calibration stages still follow the baseline score.

The existing exact registration/capacity/privacy/network/provider admission,
manual selection, fallback authority, effect ownership and transport publication
are unchanged. Scoring does not authenticate a provider or authorize disclosure.
Inferred capabilities remain soft preferences and explicit mandatory capabilities
retain their hard filter. No old token/cost/memory/battery hard budget cutoff is
reintroduced; the current telemetry-only counter policy is preserved.

## Remaining Work And Evidence

This is not the full Android router: persisted resource/domain health circuits,
health latency precedence, complete observed token/cost usage ingestion, Android
provider-family preference ordering, six-candidate failure-domain ordering and
the generic timeout/deferred-observation workflow remain incomplete. No default
healthy samples, fake usage or synthetic circuit state are inserted to mask
those missing inputs. This increment must not be reported as #3119 completion.

Six native fixture methods were authored, not executed. They cover exact weights,
network/context preferences, finite telemetry, capability-source semantics and
actual selector/stable-primary consumption. The JavaScript scope check and
project structure check are source evidence only, not Swift type correctness,
XCTest, native/device delivery, routing acceptance, performance or privacy proof.
No native build, CI monitoring or IPA was performed for this increment.

The historical `check-stable-auto-admission-scope.cjs` composes the exact ranking
hook normalizer for its old quality-source comparison. Its full execution still
fails on preexisting manual model-selection changes since its older
`ddcb2a69acd02ea12d20fb469e779d4d87b85a4f` baseline, not on this ranking hook.
The new check instead freezes current registration/admission/selector, task-budget,
provider-profile, self-model and executor sources at the stated current baseline.
No historical whole-check success is claimed.

```sh
node apps/ios/tools/check-provider-resource-ranking-scope.cjs
```
