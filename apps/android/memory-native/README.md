# Native memory index candidate

Version **0.6.0** provides the JNI backend used by Android knowledge semantic
retrieval. It replaces the transient whole-corpus JVM graph, not the authoritative
encrypted source database. This is **not a completed 100M-memory implementation**.
The isolated probe still never reads or changes App data; the App bridge maintains
its own derived index and Keystore-wrapped key.

## Dependency and design

- DiskANN is pinned to commit
  `a2373e82de8b0edea674736e7fa1c2d55b9a9f44`; `Cargo.lock` pins transitive crates.
  Upstream sources carry the MIT license. See the
  [pinned source](https://github.com/microsoft/DiskANN/tree/a2373e82de8b0edea674736e7fa1c2d55b9a9f44)
  and [license](https://github.com/microsoft/DiskANN/blob/a2373e82de8b0edea674736e7fa1c2d55b9a9f44/LICENSE).
  The GalaxySSI adapter follows the repository's Apache-2.0 license; the upstream
  MIT license remains unchanged.
- The library uses upstream graph construction/search and SIMD distance
  functions. `NodeStore` supplies authenticated vectors and adjacency lists;
  the adapter never serializes a plaintext graph or loads the entire corpus.
- Opening reads only the persisted root. All vectors, including the root and
  queries, must be normalized in the same embedding space. A zero centroid is
  rejected because it produces pathological pruning with normalized vectors.
- Decrypted node/query/prune vectors and JNI array copies use `Zeroizing`
  ownership. This does not establish whole-process zeroization: upstream scratch
  IDs/distances and operating-system copies still require memory analysis.
- Inserts require one host transaction covering the new vector and all neighbor
  changes; searches require a stable host snapshot. A failed operation propagates
  its error. The App JNI bridge and replay consumer enforce those boundaries.
- The optional `sqlite-store` implements encrypted physical node shards and a
  durable transaction/snapshot owner. Version 0.3.0 added bounded mutation replay,
  transactional provenance and stale-source filtering. The `android-jni` feature
  adds opaque handle ownership, synchronous bounded calls and cancellation.
  Android validates source revisions and access policy after candidate retrieval.
- A bounded transaction-local node cache avoids repeated row decryption during
  graph construction. It shares the configured cache budget with SQLite pagers,
  never survives commit/rollback and never bypasses cancellation or source checks.
  Its maximum is 4MiB; small budgets leave the cache disabled rather than raising
  the requested memory target. See [scale measurements](../../../docs/architecture/android-native-memory-scale.md).
- New high-dimensional nodes use the pinned DiskANN scalar SQ8 quantizer when
  normalized reconstruction squared-L2 error is at most `0.0001`. Smaller than
  128-dimensional vectors keep FP32. Higher-error vectors try IEEE FP16 with the
  same error check before retaining FP32. Authenticated nodes v2/v3 store immutable
  SQ8/FP16 bytes; v1 remains readable and is not rewritten on opening.
  Both working vectors and byte codes count toward the fixed cache target and are
  wiped on release. See [compact node design](../../../docs/architecture/android-memory-compact-nodes.md).

Source state, node provenance and replay checkpoints now share the physical
node shards. Existing catalog records migrate in authenticated, bounded
background transactions without rebuilding graph nodes. See
[record sharding and recovery](../../../docs/architecture/android-native-record-shards.md).

## Build prerequisites

Windows validation uses Rust **1.97.1, x86_64-pc-windows-gnu**, with the
`aarch64-linux-android` standard library, the `rustfmt` component, and Android
NDK **29.0.13113456**.
The development cache is `build/native-memory-deps/{cargo,rustup}`; callers may
pass another cache using `-CargoHome` and `-RustupHome`. Do not check toolchains or
`target/` artifacts into Git. Rustup can install into these directories by setting
`CARGO_HOME` and `RUSTUP_HOME`, using `--profile minimal --no-modify-path`.
The native adapter adds no model downloads. Android builds package the separate
`libgalaxyssi_memory_native.so`; they do not alter Whisper/QNN or GGML libraries.

Before the first offline build, use this Cargo environment to fetch the locked
dependencies with `cargo fetch --locked --manifest-path apps/android/memory-native/Cargo.toml`.
The host build uses the NDK's `llvm-dlltool` for Windows GNU import libraries;
the Android linker is `aarch64-linux-android26-clang.cmd`. Android ELF load segments
are built and checked at 16KiB alignment. This is not a 16KiB-device/JNI smoke test.

From the repository root:

```powershell
./tools/dev/test-memory-native.ps1 -Mode host
./tools/dev/test-memory-native.ps1 -Mode android
./tools/dev/test-memory-native.ps1 -Mode sqlite-android
```

The Android runner is restricted to **SM-T575**. It uploads a native executable
and creates a unique synthetic fixture under `/data/local/tmp`; it never accesses
App databases, pairing, models or private user memory. Raw evidence is written
under `build/memory-native-evidence/<run-id>/`.
The `Native Memory Adapter` workflow runs formatting and locked host regression
tests on changes to this module. It is not a replacement for Android device or
production App integration tests.

`host` tests the core adapter and builds the small file probe without requiring
a Windows C compiler. `sqlite-android` builds the bundled SQLite storage tests
with NDK Clang and executes them on SM-T575. Linux CI tests **all features**,
including SQLite. A Windows all-feature host build additionally needs a Windows
GNU C toolchain; the NDK Android C compiler is not a Windows C compiler.

SQLite storage builds must set `LIBSQLITE3_FLAGS=-DSQLITE_MAX_ATTACHED=64`.
Both the Android runner and CI do this explicitly. An incompatible build fails
on open instead of silently changing the requested shard topology. Locked
`rusqlite` 0.40.1 uses bundled `libsqlite3-sys` 0.38.2; these are optional native
dependencies, not a replacement for the App's existing SQLite engine.

Android Gradle's `buildNativeMemory` task invokes `tools/dev/build-memory-native.mjs`.
It builds the locked `android-jni` feature from source with the pinned NDK and
verifies 16KiB ELF LOAD alignment before staging the library. No developer-machine
binary is required. Set `CARGO_HOME`/`RUSTUP_HOME` or install the pinned toolchain
in the development cache described above. Gradle offline mode also makes Cargo
offline; run `cargo fetch --locked` beforehand. CI uses the local
`setup-native-memory` composite action to install Rust 1.97.1 and the Android target.
The release profile permits unwinding so JNI boundaries can contain Rust panics;
an allocation abort or operating-system process kill is not caught by this layer.

The optional `probe` binary uses **64 synthetic vectors and a public test key**.
Its file-per-node fixture only exercises encrypted disk access and reopening; it
is deliberately not a production layout, Keystore implementation, transaction
engine or scale benchmark. Passing it cannot establish semantic quality, 100M
capacity, deletion guarantees, or a 200ms production recall bound.

## Remaining acceptance

Test the App/JNI bridge and source/index generation lifecycle, then measure
deletion residue, source revision changes, cold/warm RSS and actual query recall against
exact ground truth at increasing cardinalities. Real BGE semantic cases and
end-to-end Agent hybrid recall are required separately from synthetic I/O tests.

See [SQLite shard design and evidence](../../../docs/architecture/android-native-memory-sqlite-shards.md)
for storage invariants, regression scope and remaining integration barriers.
See [native source replay](../../../docs/architecture/android-native-memory-replay.md)
for checkpoint, retry and source visibility contracts.
See [Android native activation](../../../docs/architecture/android-native-memory-activation.md)
for App lifecycle, replay scheduling and remaining scale acceptance.
