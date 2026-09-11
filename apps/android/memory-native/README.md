# Native memory index candidate

This module is **not yet wired into the production Android Agent recall path**.
It is the storage-access adapter for the next disk-backed vector index, not a
completed 100M-memory implementation. The existing App and its Keystore data are
unchanged by building or running the isolated probe.

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
- Decrypted node/query/prune vectors use `Zeroizing` ownership. This does not
  establish whole-process zeroization: upstream scratch IDs/distances and the
  future JNI/host cache still require lifecycle and memory testing.
- Inserts require one host transaction covering the new vector and all neighbor
  changes; searches require a stable host snapshot. A failed operation propagates
  its error. The App bridge must enforce those boundaries before activation.
- The optional `sqlite-store` implements encrypted physical node shards and a
  durable transaction/snapshot owner. Source/model mapping, mutation replay,
  deletion, source revision validation, shared cache admission and JNI ownership
  are still integration work. No production feature flag enables this module.

## Build prerequisites

Windows validation uses Rust **1.97.1, x86_64-pc-windows-gnu**, with the
`aarch64-linux-android` standard library, the `rustfmt` component, and Android
NDK **29.0.13113456**.
The development cache is `build/native-memory-deps/{cargo,rustup}`; callers may
pass another cache using `-CargoHome` and `-RustupHome`. Do not check toolchains or
`target/` artifacts into Git. Rustup can install into these directories by setting
`CARGO_HOME` and `RUSTUP_HOME`, using `--profile minimal --no-modify-path`.
The native adapter adds no model downloads or Android runtime dependencies yet.

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

The optional `probe` binary uses **64 synthetic vectors and a public test key**.
Its file-per-node fixture only exercises encrypted disk access and reopening; it
is deliberately not a production layout, Keystore implementation, transaction
engine or scale benchmark. Passing it cannot establish semantic quality, 100M
capacity, deletion guarantees, or a 200ms production recall bound.

## Remaining acceptance

Complete the App/JNI bridge and source/index generation lifecycle, then test
deletion residue, source revision changes, cold/warm RSS and actual query recall against
exact ground truth at increasing cardinalities. Real BGE semantic cases and
end-to-end Agent hybrid recall are required separately from synthetic I/O tests.

See [SQLite shard design and evidence](../../../docs/architecture/android-native-memory-sqlite-shards.md)
for storage invariants, regression scope and remaining integration barriers.
