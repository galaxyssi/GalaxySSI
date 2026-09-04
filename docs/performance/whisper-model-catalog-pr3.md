# Whisper Model Catalog and Verified Storage

PR-3 replaces the legacy size-only Whisper download check with a pinned, multi-model catalog and a verified private installation pipeline.

## Supported profiles

The catalog preserves `tiny`, `base`, `small`, `medium`, and `large`. It also defines controlled quantized profiles and both Large v3 Turbo variants. Every profile pins its family, file name, exact byte count, SHA-256 digest, execution recommendation, memory budget, and trusted HTTPS sources.

Only Tiny is bundled with the Android package. Medium, Large v3, and Large v3 Turbo remain optional downloads.

## Trust boundary

Downloaded and legacy files are never loaded directly by whisper.cpp. GalaxySSI now:

1. checks free space before enqueueing a download;
2. downloads to an app-scoped `.partial` path;
3. validates exact size and SHA-256;
4. copies and fsyncs into a private staging path;
5. atomically moves the verified file into private model storage;
6. writes pinned installation metadata atomically;
7. verifies the full digest again before the first native load in each process.

An interrupted copy, truncated download, stale metadata, changed digest, or unknown manifest path cannot enter the native runtime.

## Migration and certification

Existing Tiny/Base/Small/Medium/Large files are migrated only after exact catalog verification. The bundled Tiny asset follows the same verified migration path on first use.

New installations are marked `INSTALLED_UNCERTIFIED`. The UI does not claim real-time capability until a later device benchmark certifies the profile. Model certification and JNI session work continue in the following PRs defined by the latency optimization specification.
