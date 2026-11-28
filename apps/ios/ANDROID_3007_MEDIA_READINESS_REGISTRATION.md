# Media Readiness Registration

iOS-only follow-up found during the Android #3007 startup/catalog audit, based
on main c6bad3465c673dfb2dcecb23b095185c129c7447. This is not a claim that #3007
directly changed these iOS media counterparts or that its full port is complete.

The media catalog formerly captured readiness only at construction. In the real
signed FFmpeg provider, transcode readiness flows through the on-device runtime
adapter to the runtime execute capability. The catalog could remain blocked
after setup or expose stale readiness after runtime failure.

All three media definitions now use their exact kind's live availability
callback. Default registry construction supplies an unavailable/not-yet-checked
initial descriptor instead of probing media/runtime availability during
registration. Explicit definition/executable-helper calls default to nil and
retain eager initial snapshots. Registry descriptor discovery/refresh and actual
invocation resolve the provider dynamically. A caller-supplied initial snapshot
cannot override that live gate.

Tool contracts, permissions/consents, content URI handling, security-scoped file
access, playback handoff-only semantics, offline typed FFmpeg execution, workspace
limits, artifact/receipt validation, runtime adapter and providers are unchanged.
No media bytes are read, runtime started or conversion retried by availability.
Readiness is not proof the guest has a working FFmpeg binary, a permission grant
or a completed conversion. Provider constructors/other startup paths remain
outside this increment; descriptor queries retain the existing cache/refresh.

Eight Swift fixtures are authored in the existing registered media test file,
not executed: eager compatibility, deferred registration, executable-helper
forwarding, refresh/recovery/failure and operation isolation, live invocation,
untrusted available-snapshot rejection, permission/consent enforcement, and
readiness propagation through the real signed-media/runtime-adapter chain.
Synthetic executors never inspect/play/transcode a file or invoke Linux.

Exact source guards, iOS project structure and whitespace checks are permitted;
they do not establish Swift type checking or native/runtime acceptance. No
Swift/native build, XCTest execution, live media/network/model, simulator/device,
full repository check, CI inspection or IPA generation is included.
