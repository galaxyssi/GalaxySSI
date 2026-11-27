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
No new timer or cache is introduced, and construction-time probes still occur.

The four callbacks are the only application changes. Initial descriptors,
wire IDs, schemas, risks, permissions, consents, execution/recovery, Git network
and publication policy, signed runtime/pack validation and QEMU lifecycle remain
unchanged. Readiness is not a permission grant or successful-execution receipt.

## Verification

The dedicated source guard checks the exact approved definition blocks and
compares every other line in all four files with main. Twelve negative source
mutations reject fabricated/stale providers or unrelated changes. Registry/core,
runtime provider and QEMU files are frozen. The only optional composition is the
exact independent MCP registration delta in the catalog from #4685.

Eight XCTest methods are authored, not compiled or executed: four registry
refresh cases for setup/recovery/failure, and four invocation-gate fixtures with
live readiness and missing permissions. Invocation fixtures use a synthetic
failure executor and do not start a provider, VM, Git command or evolution task.
They are not end-to-end provider acceptance.

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

This does not remove construction-time runtime probes, install missing Linux
assets, prove guest health, start a runtime, repair failed tasks or add a new
authorization. Full startup/background preparation, generic routing parity and
native/runtime/performance acceptance remain incomplete.
