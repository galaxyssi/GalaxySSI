# Agent Home Native Catalog Worker

Independent increment from main
`c6bad3465c673dfb2dcecb23b095185c129c7447`. Android #3007 moves catalog prewarm
onto the navigation-content worker. iOS home still rebuilt descriptors during
every automatic-route warning projection and again for its runtime panel.

Use one profile-owned StateObject loader for both active home display consumers.
The catalog factory is captured as a closure, never called during view/loader
initialization. A separate serial utility queue reads it; MainActor publishes
the complete descriptor snapshot. Reuse the existing unchanged dashboard refresh
state for exact completion tokens, identity invalidation and one trailing refresh
after a burst. Old completions cannot replace a new owner's result. A failed
refresh retains its last complete display snapshot; a successfully empty catalog
is distinct from an unknown/not-yet-loaded catalog.

Home no longer calls descriptors from its warning/count or runtime-panel view
projection. Unknown initial state suppresses the advisory "No ready models"
warning rather than interpreting a pending load as zero ready tools. The runtime
toolbox uses the existing localized Loading text while its first snapshot is
pending. Other runtime-panel callers retain their default behavior. Effective
tool permission/risk filtering and all task controls remain unchanged.

Refresh on visible unlocked foreground entry, profile/boundary changes, existing
routing notifications and every 30 active-visible seconds. Invalidate immediately
on disappearance, backgrounding and plaintext clear. A matching current profile
and readable transcript boundary are required even before showing a snapshot.
Offscreen notification/poll requests cannot reactivate an invalidated loader.
The catalog is display data, not an execution/routing authorization source.

Six XCTest methods authored and registered, NOT executed: reads off the caller
with actual availability/risk counts; burst coalescing; old-profile completion
containment; failed refresh retention; invalidation/offscreen no-reactivation;
and unknown versus successful empty state. They inject synthetic descriptor
arrays and queues; no real providers, SwiftUI lifecycle, device permissions or
performance acceptance are executed.

The source guard pins feature commit
`a08d14423c650da7fef28d24800f755323909eef`, compares complete home/control sources
outside only declared projection/lifecycle/loading hooks, freezes the existing
catalog/routing/refresh-state kernels and checks all eight exact Xcode entries.
It rejects lifecycle weakening and confirms the actual factory runs only inside
the worker path. Dedicated source, JS syntax, project and whitespace checks pass.

No Swift/native build, XCTest execution, full check, CI watching, IPA, private
evidence upload or native/rendering/performance acceptance. This does NOT move
mandatory execution-runtime construction, audit/context reads, every other home
projection or other pages off MainActor. Runtime-only changes without a routing
notification can wait for the next visible refresh. Already queued synchronous
reads are not forcibly interrupted, and profile churn is not a bounded global
work-queue guarantee. Full Android #3007/backlog completion remains unproven.
