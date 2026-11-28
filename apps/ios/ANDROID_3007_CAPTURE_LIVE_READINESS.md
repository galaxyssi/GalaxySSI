# Capture Live Readiness

iOS-only follow-up discovered during the Android #3007 catalog/startup audit,
based on main c6bad3465c673dfb2dcecb23b095185c129c7447. This is not a claim that
#3007 directly changed these two iOS definitions or that its full port is done.

Photo/audio definitions captured provider availability at creation. A busy or
permission-denied snapshot could remain after capture ended or Settings changed.
Both definitions now use their own kind's live provider callback. Discovery and
refresh update cached descriptors; each new invocation checks current readiness.
The production registry supplies an unavailable/not-yet-checked initial snapshot
without initial capture-provider permission/main-queue probes. Explicit catalog
and executable-helper calls preserve eager nil-default behavior. An injected
available initial snapshot does not override the live admission gate.

The provider, capture executor, system permission request/preflight, foreground
checks, busy coordinator, visible presentation, duration limits and artifact
verification are unchanged. Readiness may allow an undetermined OS permission;
it is not a permission grant. Existing invocation permissions and both consents
still apply, as do the provider's later OS checks. No hidden/background capture,
automatic reexecution, new permission prompt or effect cancellation is added.
Descriptor cache behavior and other constructor/startup work are not replaced.

Eight Swift fixtures are authored in the existing registered capture test file,
not executed. They cover eager/deferred registration, executable-helper forwarding,
busy/denied-to-ready refresh, independent photo/audio states, per-invocation live
checks, fabricated initial availability and missing permissions/each consent.
Synthetic executors never open a camera, microphone or permission dialog. Source
checks pin the exact catalog hooks and freeze provider/executor/permission paths;
they are not concurrency, OS callback, UI, device or successful capture acceptance.

No Swift/native compilation, XCTest execution, simulator/device/live media,
full repository check, CI inspection or IPA generation is included.
