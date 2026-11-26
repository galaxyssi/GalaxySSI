# Android #3025: private receive-stage diagnostics

Android reference: cef237557f5f8f422f93832a535e3d63e3ba81ed (#3025).
Incremental iOS parent: 2d6678d8aed5cd0d9bf9afff051efaca00c9c931. This is another
commit on #4610, not a second PR for the same Android change.

## Actual stage boundaries

- wire_open: authenticated outer packet opening in GalaxySSIMqttClient, including
  the failure path. This is not Signal session decryption.
- queue: from yielding authenticated ingress to consuming it on the existing
  bounded AsyncStream. It excludes socket reception and outer packet opening.
- handle: the existing asynchronous business receive method, including routing,
  identity checking, decrypt/store or chunk/control handling and receipt work.
- signal_decrypt_store: both direct Signal and completed/recovered chunk paths.
  The existing API decrypts and stores together; this timer cannot claim to
  isolate cryptographic CPU time from database work.
- inbox_dispatch: one existing pending-inbox do block, including decoding,
  projection, durable completion and revocation handling. It is not a rendered
  UI first-frame or full end-to-end delivery measurement.

All durations use DispatchTime monotonic nanoseconds converted to milliseconds.
Asynchronous spans include waits and actor scheduling, not only CPU execution.
The stage allowlist and numeric elapsed duration are the only logged values.
No body, topic, contact, identity, task/message ID, plaintext fragment, error text
or URL enters this diagnostic channel. No new persistent history or telemetry
upload is added. DEBUG alone enables the clock reads, Logger and log calls;
Release wrappers take no timestamps and emit no logs.

The ingress wrapper keeps the original bufferingOldest(32) policy and delivery
loop. The synchronous measurement wrapper returns/throws the original result
exactly once; deferred logging covers failures without consuming them. Existing
Signal/journal/route/inbox implementations, ACK/admission/receipt sequencing,
authenticated ingress checks, task concurrency and encrypted wire bytes remain
unchanged. These are diagnostic probes, not a change to delivery reliability or
a fix for any pre-existing queue overflow behavior.

## Verification boundaries

Three additional Swift methods are authored for the fixed stage vocabulary,
duration underflow/overflow boundaries and return/throw/single-call propagation.
The complete #4610 branch now authors twelve new methods. No native compilation,
test execution, log capture, real Signal/database timing or device performance
acceptance is claimed. Source guards compare retained production code against
the incremental parent and confirm DEBUG containment and existing ingress bounds.
They do not prove runtime log redaction or measured latency.

No CI watching, IPA or raw/private evidence is included. A later increment fixes
linked-image wrapper and URI identity issues in ANDROID_3025_ORDERED_IMAGE_REPLIES.md;
full ordered-image/task-local-caption equivalence remains unverified. All Android
and Desktop runtime sources remain unchanged.
