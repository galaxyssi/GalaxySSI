# Settings Runtime Summary Worker

Independent iOS increment on main
`c6bad3465c673dfb2dcecb23b095185c129c7447`, following Android #3007's separation
of native catalog/context preparation from routing/UI work. The pinned Android
MainActivity diff moves catalog/context prewarm to navigationContentExecutor.
This increment fixes the actual iOS settings-summary hot path, not the whole
mandatory native runtime initializer.

## Change

SwiftUI's settings task ID and navigation prewarm key previously rebuilt the
entire native catalog, read MCP files and decoded local model settings on
MainActor. A cache miss then repeated catalog/MCP scans in a background task.
The UI key now uses the existing store summary inputs and current profile only.
Existing point session counts and in-memory store projections still run on
MainActor; this is not a claim of zero UI-thread I/O or all-page optimization.

Load runtime metadata in a detached utility task and reuse one catalog/MCP scan
for both invalidation identity and aggregate counts, including cache hits. No
runtime value is frozen forever. Native availability and blocked risk, MCP enabled
state and actual isCallable at the snapshot clock, and local model configuration
participate in the worker-produced key. Authentication expiry therefore changes
the key even if the saved connection state does not change.

Use a 30-second monotonic summary cache rather than wall time. A generation,
cancellation and current store-source check prevent an older preparation from
replacing a newer shared cache entry. Cache lookup includes profile identity.
The page clears old counts when its profile changes and rejects late results
after cancellation, disappearance, backgrounding or a changed navigation owner.

Refresh on visible foreground entry, routing notifications delivered on main,
and every 30 foreground-visible seconds. Structured task identity includes
visibility/scene phase; disappearance explicitly disables the loop. Runtime-only
changes without a routing notification can take up to the next refresh to appear.
Do not erase the current display or flash a loading placeholder on each poll.
Initial prewarm may show its prior summary briefly while fresh work completes.
Synchronous provider scans already in flight are not forcibly interrupted.

Descriptors/providers, native execution, MCP auth/permission semantics, route
selection and transport are unchanged. Counts remain summaries, not authorization
to execute a tool. No new provider probe/model call/network request is introduced.

## Verification

Six XCTest methods authored and registered, NOT executed: native risk/availability
counts; runtime-key changes; MCP expiry/disable/error/endpoint readiness; value
isolation and no title/endpoint in keys; monotonic freshness boundaries; and empty
projection without fabricated readiness. These do not exercise SwiftUI lifecycle,
concurrent cache preparation, native provider construction or real MCP files.

The source guard pins the exact production increment to
`bf68594c9ac3ea6f66a6782e3528228c11ddea3d`, compares the complete settings source
after only declared hooks, checks worker-only factory placement and one scan per
preparation, and freezes catalog/MCP/navigation dependencies. It also checks the
four exact test project registrations and rejects synthetic stale/lifecycle
weakening. Dedicated source, JS syntax, iOS project structure and whitespace
checks pass; these are not measured latency or Swift compiler evidence.

No native build, XCTest execution, full check, CI monitoring, IPA, private evidence
upload, simulator/device/rendering/performance acceptance. Native runtime startup
prewarm, other pages' catalog work and the full Android backlog remain incomplete.
