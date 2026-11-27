# Deferred MCP registration readiness

Independent Android #3007 startup-preparation follow-up, based on main
`c6bad3465c673dfb2dcecb23b095185c129c7447`. No other pending feature is included.

## Actual connection

The mandatory native registry previously evaluated MCP provider availability while
constructing each MCP definition. For the default MCP provider, tools/list and
tool/call readiness consult the connection store. Definition registration does
not execute a tool and the registry already resolves dynamic availability for
descriptor queries and each invocation; those construction-time reads are now
unnecessary on this path.

- The real registry factory supplies an explicitly unchecked/unavailable initial
  descriptor, not a fabricated ready snapshot. MCP executable registrations and
  contracts remain installed. There is no model-selected permission bypass.
- Direct catalog and existing custom helper calls retain their eager default;
  only callers supplying an initial snapshot opt out of construction-time probes.
- The existing dynamic provider remains authoritative for registry descriptor
  resolution and invocation. Connection, authentication, permission, deadline,
  executor and result handling are unchanged.
- Exact local-tool discovery now resolves the requested definition's current
  availability after invalidation. It previously returned the static construction
  snapshot even after refresh. It checks the existing scoped authorizer first
  and does not scan every other provider for a one-tool query.
- Paginated discovery, registered-contract identity and input contracts retain
  their existing behavior. Structural lookup still returns the initial descriptor;
  it is not a runtime readiness query.

## Verification limits

The source guard normalizes only the exact approved three-file changes, compares
all remaining source against main, freezes registry/provider/permission kernels,
rejects seven unsafe or unrelated mutations and checks Xcode test registration.

Eight XCTest methods are authored, not executed: eager compatibility, deferred
registration, live exact discovery, dynamic invocation, unavailable provider,
missing permission, stable registered-contract identity and unknown-tool isolation.
These do not prove real connection-store timing, native delivery or startup speed.
No Swift/native build, XCTest, full repository check, CI inspection, simulator/
device/live model/network execution, IPA or private evidence is included.

## Remaining work

This removes MCP construction-time readiness reads, not all native registry or
provider initialization. Actual descriptor/discovery/invocation checks remain
synchronous on their existing callers; this is not a new background MCP executor.
No continuous readiness subscription, new cache, network access or capability is
added. Existing registry thread-safety and cross-process storage are unchanged.
Full Android parity and native/runtime/performance acceptance remain incomplete.
