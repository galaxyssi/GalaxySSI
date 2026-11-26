# Android #3025: idle mobile model connections

Android reference remains cef237557f5f8f422f93832a535e3d63e3ba81ed (#3025).
Incremental parent: 1a9f176ca540b177d756ccac5be4685c5cfc9295 (the initial #4610
image-request correction). This follow-up stays on the same Android-corresponding
iOS PR rather than opening a duplicate.

## Foundation adaptation

The production cloud streaming client now acquires an owned ephemeral URLSession
through a small locked pool. After the last response-body lease ends, an idle
interval of at least 60 seconds causes replacement before the next request. No
background timer or new network request is scheduled. Thus an old session may
remain allocated while unused, but it is not reused after the idle threshold.

Leases span headers, error bodies, complete JSON and the full SSE/JSON-lines body,
including failure/cancellation exits. Concurrent streams keep the current session
alive regardless of their age. Ending a lease is idempotent; lease destruction
also releases it. Retirement happens outside the pool lock and uses
[finishTasksAndInvalidate](https://developer.apple.com/documentation/foundation/urlsession/finishtasksandinvalidate())
instead of cancelling active tasks. Injected sessions remain caller-owned and
are never replaced or invalidated by the pool. The clock uses the client's
monotonic elapsed-time source with overflow-safe comparison.

The existing ephemeral configuration, eight per-host connections, request/resource
timeouts, active per-request read settings, provider adapters and redirect policy
are unchanged. The exact single-request host-trial transport branches before
acquiring a pooled session and remains unchanged. No POST retry, request replay,
task-concurrency reduction, Connection header manipulation or URLSession private
API is added. This is session rotation, not a claim that Foundation exposes the
same per-socket idle pool or HTTP2 ping controls as OkHttp. HTTP2 ping behavior,
actual socket reuse and weak-network recovery remain unverified.

## Verification boundaries

Four additional Swift methods are authored for reuse before/at the idle boundary,
long concurrent body leases and duplicate release, caller-owned injection, and
destructor/overflow/clock-rollback behavior. They are not compiled or executed.
Combined with the initial increment this PR authors nine new test methods.
Scoped JavaScript checks verify call placement, ownership, unchanged active/trial
paths and retained code only; they do not execute URLSession or prove TCP-level
behavior. No native/model/network/device tests, latency measurement, CI monitoring
or IPA are performed. MQTT stage diagnostics, ordered-image/caption equivalence
and overall Android parity remain separate work.
