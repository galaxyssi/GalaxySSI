# Live runtime tool readiness

Independent iOS correctness follow-up discovered during the Android #3007 native
catalog/startup audit. Base: `c6bad3465c673dfb2dcecb23b095185c129c7447`.
This is not a claim that #3007 directly changed these four Android counterparts.

## Production connection

Linux/runtime, project repository reads, project repository mutations and
self-evolution definitions captured provider availability only at construction.
Without a dynamic availability provider, the existing registry refresh and
per-invocation resolution could only reuse that old snapshot. Tools could remain
blocked after setup, or remain described as ready after provider failure.

Each family now supplies the existing dynamic availability callback. Runtime
and evolution definitions query their own exact operation; both Git families
query the runtime's execute capability. The registry's existing descriptor cache,
explicit refresh and each invocation use the current provider status/reason.
No new timer or cache is introduced.

The actual registry construction path now explicitly supplies an unavailable,
not-yet-checked initial descriptor for these four families. Constructing and
registering their 27 definitions does not call provider availability. Registry
discovery/refresh and invocation still resolve live readiness through the same
callbacks. This avoids initial Linux/broker/pack/store probes; it does not make
provider constructors or all startup work asynchronous.

The optional initial-availability argument defaults to nil, preserving eager
compatibility for explicit catalog/helper callers. It never overrides the live
callback. Tool wire IDs, schemas, risks, permissions, consents, execution/recovery, Git network
and publication policy, signed runtime/pack validation and QEMU lifecycle remain
unchanged. Readiness is not a permission grant or successful-execution receipt.

## Verification

The dedicated source guard pins all four complete definition files and the exact
four registry/helper registration deltas. Negative source mutations reject
fabricated/stale providers, eager production registration and unrelated changes.
Registry/core, runtime provider and QEMU files are frozen. Exact independent MCP
registration deltas in #4685 compose through its existing source normalizer.

Thirteen XCTest methods are authored, not compiled or executed: four registry
refresh cases for setup/recovery/failure, and four invocation-gate fixtures with
live readiness and missing permissions. Invocation fixtures use a synthetic
failure executor and do not start a provider, VM, Git command or evolution task.
Five additional cases cover all four deferred catalogs and executable-helper
forwarding: zero probes during definition/registration/fingerprinting, live first
discovery, refresh after setup, stable contract identity and eager nil-default
compatibility. They are not end-to-end provider acceptance.

No Swift/native build, XCTest execution, full repository check, CI inspection,
simulator/device/live network/model execution, IPA or private evidence is included.

Local integration with sixteen pending branches (#4664 and #4671-#4685) had no
textual or Xcode registration conflict. All twenty-two focused source guards,
`npm run check:ios` and `git diff --check` passed on that combined tree. No guard
in another branch required modification for this change. The registry's original
committed-result replay precedes live admission and remains untouched; no remote
PR is approved or merged by this verification.

## Remaining work

There is no continuous readiness notification. Descriptor snapshots follow the
existing five-second cache or explicit refresh; actual invocation rechecks the
provider. Structural definition lookup still returns its initial snapshot.
Exact discovery is corrected separately in #4685; no code from it is included.

Explicit eager catalog calls can still probe synchronously. This does not install missing Linux
assets, prove guest health, start a runtime, repair failed tasks or add a new
authorization. Full startup/background preparation, generic routing parity and
native/runtime/performance acceptance remain incomplete.
