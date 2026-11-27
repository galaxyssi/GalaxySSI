# Android #3030: retrieval publication cancellation

Reference: a3b9d025fa61625a53bdcd13845c1e6be38555d6 (#3030).
Independent iOS base: 8a794e82ebe8f09790e41139295ffb7ac1ee9701 (main).

## Existing implementation and observed gap

Main already includes the earlier iOS read-snapshot/contention implementation
(826723225). This increment does not duplicate its WAL snapshot, selected-source
validation, payload lifetime or ranking code. It addresses the caller-task
publication boundary emphasized by Android's final cancellation recheck.

The busy-admission lexical fallback awaited its serial queue and returned hits
without checking the calling Swift task's cancellation. The full hybrid path
checked a request-specific cancellation flag on the queue, but had no final
caller-context check after its continuation resumed. A lifecycle token could
also change between the queue check and resuming the awaiting caller.

After either await completes, check Task cancellation and the current native-file
lifecycle token immediately before returning evidence. Check an already-cancelled
request before admission/embedding starts. Preserve the existing request-owned
native cancellation handler; cancelling a busy fallback does not invalidate the
database generation or cancel another owner's admitted work. Queue/database work
is not force-aborted by these final checks. This is a publication boundary, not
an atomic guarantee against every mutation that occurs after the final check.

## Deterministic fixture boundary

The production runtime initializer still delegates embedding to the same
GalaxySSIEmbeddingRuntime. An internal closure/factory initializer permits tests
without loading a real model/native graph. A default no-op publication callback
allows synthetic tests to pause after SQLite validation, then cancel or invalidate
the lifecycle before releasing the worker. No payload is passed to this callback.
Production callers and embedding/native behavior are unchanged apart from final
publication checks. Native index/session protocols are not modified here.

Six new Swift methods are authored for normal busy fallback, cancelled fallback
and hybrid publication, lifecycle invalidation of both paths, pre-cancelled work,
normal ranking and admission release. They use the real lexical database and
simulate only embedding/native graph operations. They have not been compiled or
executed. The controlled tests cover cancellation while the publication callback
is blocked; they do not establish acceptance of every post-continuation scheduling
interleaving, native SQLite/Signal faults or device lifecycle scenario.

## Scope and verification limits

Source guards retain surrounding ranking, queue/request ownership, active native
cleanup and the database/index/files/controller kernels. No schema, ACL, source
revision, backup, crypto or model-download behavior changes. Existing Android
performance figures and process-death tests are not transferred to iOS acceptance.
Complete same-view retrieval, writer/payload concurrency and scale acceptance are
not newly certified by this increment, and the Android-to-iOS backlog remains.
No Swift/Rust compilation, XCTest execution, native/device acceptance, CI watching
or IPA is performed. Android/Desktop code and versions and iOS 15 minimum remain
unchanged. No raw reports or private data are committed.
