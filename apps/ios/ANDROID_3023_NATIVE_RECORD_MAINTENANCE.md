# Android #3023: native provenance record maintenance

Android reference: #3023, merge 0eb47b7ef6681e6cd80b0cde345e844fd805cd17.
This independent iOS branch starts from main
8a794e82ebe8f09790e41139295ffb7ac1ee9701. It does not inherit the unmerged
authoritative-primary storage series (#4596, #4600-#4608).

## Existing shared implementation versus missing iOS integration

The iOS memory crate already pins the shared Rust library at 0.6.0, containing
authenticated record layouts and resumable cross-shard migration. No Rust engine,
Android source, schema, key format, cache budget or graph/provenance rule is
duplicated or changed here. Previously the iOS C ABI could not invoke its layout
query or migration methods, so merely linking that library did not schedule legacy
record migration.

Two additive C exports now expose the existing engine methods through the same
serialized, cancellable owner. A checked caller-owned byte reports completion;
errors clear it and must not be interpreted as successful migration. Migration
accepts 1..256 records per transaction. Existing open/configuration ABI version 1,
buffer formats and symbols remain compatible; the framework export allowlist is
expanded explicitly rather than exposing bundled SQLite symbols.

The Swift bridge validates flags and bounds. NativeIndex maintenance requires an
explicit background lease and its matching generation. Foreground replay/search
do not call the migration method. Background slices perform one 64-record page
even when replay is already ready, skip writes for a partitioned layout, preserve
unfinished intent and reject late results after lease expiry. Migration failure
retires the current session; durable progress belongs to the existing Rust engine,
not to a new in-memory Swift cursor or a destructive rebuild.

Foreground completion no longer clears background intent solely because vectors
and replay are ready. An enabled/installed index requests a system task to confirm
record layout; the background result clears intent only when enrollment, vector
work, replay and record migration are all complete. Each request is still subject
to iOS scheduling, protected-data gates, cancellation and lifecycle generation
fences. No periodic execution or latency guarantee is added. The existing
embedding-runtime prerequisite remains; model-free native maintenance is not
claimed by this change.

## Verification boundaries

Seven new Swift tests simulate the session boundary for ready/partitioned graphs,
foreground nonmigration, invalid page sizes, expired leases, migration failures,
late completion and owner recreation. Three new Rust tests exercise checked C
outputs, bounds, cancellation/closed handles and idempotent already-partitioned
store maintenance with checkpoint preservation across reopen. These are authored
source, not executed results. The new C tests do not seed a legacy encrypted
layout, so they are not proof of legacy-file migration on iOS. Shared Android
legacy/corruption tests and measurements are not transferred as iOS acceptance.

Scoped JavaScript checks retain unaffected Swift replay/search and surrounding
ABI code, check actual background call/intent propagation, compare C declarations
and exports, and preserve the shared engine source. No Rust/Swift compilation,
native test execution, device acceptance, CI watching or IPA is performed. Full
capacity, performance, process-exit recovery and platform-wide Android parity
remain unverified. This is provenance-record migration, not authoritative source
partitioning or completion of the overall Android-to-iOS backlog.
