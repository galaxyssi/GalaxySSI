# iOS Knowledge Memory C ABI

Source integration for the native engine introduced by Android #3005. The iOS
crate reuses the repository's current `apps/android/memory-native` Rust engine
as a path dependency (currently 0.6.0), without JNI. It does not copy the old
0.4.0 engine from #3005 or modify Android. Current public Rust APIs were inspected
alongside the pinned #3005 behavior. Later engine additions are not claimed as
fully integrated iOS features by this bridge.
The path dependency's version is constrained to exactly 0.6.0 so a later engine
version change requires an explicit bridge audit rather than silent adoption.

The exported header is `include/GalaxySSIMemory.h`. Monotonic opaque handles
retain synchronized owners, not raw pointers. Cancel/close retire handles without
waiting on an active engine operation; an in-flight operation retains its owner.
Rust panic unwinding is contained at each C entry point. A poisoned engine must
be closed and reopened. Errors return generic status codes, not source paths or
private error strings. No network calls or application error logging are added.

Inputs are checked before copies: dimensions 1..8192, shards 1..64, cache budget
up to 256 MiB, 1..64 append chunks and 1..256 search matches. Finite vectors,
aligned non-null buffers, absolute UTF-8 paths, exact event lengths and output
capacity are checked. As with all C APIs, validity/lifetime/non-overlap of the
memory behind pointers is the caller's responsibility; arbitrary dangling
pointers cannot be made safe by range checks. Output capacity is validated
before mutating replay operations. Status errors do not prove rollback if an
operation failed after committing: callers reconcile the durable checkpoint.

Keys and copied vectors/metadata are zeroized on drop. The caller must clear its
configuration/key and all borrowed buffers after use, including error paths.
Native result data is copied into caller-owned output and native temporary
records are zeroized. No Rust allocation crosses the C ownership boundary.

## Integration Status

Xcode now builds this dynamic framework with `tools/build-knowledge-native.cjs`,
links it, and embeds it using CodeSignOnCopy. The script installs pinned Rust
1.97.1 through an already-installed rustup, builds locked release dependencies
for device arm64 or simulator arm64/x86_64, sets iOS 15.0, restricts exports to
`exports.txt`, and checks exports for SQLite leakage. Missing tooling/binaries
fail the build; no empty stub or disabled native mode is supplied. The developer
machine/CI must have rustup, Node.js and Xcode command-line tools available.

Swift source imports the module directly, decodes bounded little-endian records,
and makes synchronous borrowed-buffer calls. It handles opaque-handle retirement
and clears owned temporary configuration/vector/result buffers. This does not
replace the existing semantic search by itself.

No native compilation, dependency resolution or device test has been run. Still
required before activation:

- Verify the framework build, C/Swift ABI layout, module discovery, architecture
  slices, export isolation, signing and installation with Xcode.
- Add protected files/Keychain ownership and App lifecycle cancellation, then
  consume published-event replay pages in bounded slices.
- Handle legacy-vector reindex/bootstrap, interrupted progress and feed freshness
  before replacing the existing in-memory USearch path.

Do not claim native activation from source checks alone. Existing App retrieval
remains USearch until the production replay/query consumer is implemented.
