# Android neural embedding runtime

## Scope

`GalaxySSIEmbeddingRuntime` generates real dense neural vectors using the pinned
llama.cpp engine. It is a foundation for Memory 2.0, not a completed vector memory
integration. FTS5 remains the production knowledge retrieval path until the
embedding model lifecycle, encrypted vector index, hybrid ranking, deletion, and
retrieval-quality gates are connected.

No model is bundled in the APK. No knowledge text is sent to a remote embedding
API. The existing chat model singleton, Whisper, and QNN model paths are unchanged.
This encoder runs on CPU; it is not a QNN implementation.

## Runtime contract

- A caller opens a GGUF model and owns a `Closeable` encoder instance.
- Each instance has a separate llama model and context, not the chat singleton.
- A dedicated native handle registry serializes encoder operations and prevents
  stale pointer access. Kotlin also serializes embedding and close per instance.
- Load, embed, and nontrivial close are rejected on the main thread.
- Context, batch, and micro-batch sizes match for non-causal embedding graphs.
- Pooling comes from model metadata. CLS, mean, and last-token sequence pooling
  are accepted; unpooled outputs and reranker classification heads are rejected.
- Input uses UTF-8 byte arrays rather than JNI modified UTF-8. Tokenization is
  provided by llama.cpp, including model special tokens. Literal special-token
  text is not interpreted as control input.
- Inputs exceeding the configured token window fail without silent truncation.
  Production ingestion must split long documents into independently identified
  chunks before calling the encoder.
- Results are finite, nonzero, L2-normalized `FloatArray` values. The caller owns
  and must clear returned vectors when no longer needed.
- Owned input, token, normalized-output, and exposed sequence-output buffers are
  overwritten. The engine's private intermediate tensors are not guaranteed to
  be wiped by these APIs. Do not describe this as complete native memory erasure.
- Close releases model/context and is idempotent. There is no global backend
  shutdown, since chat may still be using that backend.

## Reproducible real-model fixture

The external test fixture is the community GGUF conversion of
[BAAI/bge-small-zh-v1.5](https://huggingface.co/BAAI/bge-small-zh-v1.5), a Chinese
embedding model using CLS pooling and normalized representations. Its model card
recommends evaluating relative retrieval ordering, not treating an arbitrary
cosine threshold as universal relevance.

- Conversion: `CompendiumLabs/bge-small-zh-v1.5-gguf`
- Revision: `5bf683e6a1bd454bbb60ba051088c50731d63fcb`
- File: `bge-small-zh-v1.5-q8_0.gguf`
- Size: 26,472,640 bytes (25.25 MiB)
- SHA-256: `5a88d266870fbd27c6f329df60de80e2d4cf3bbd5e6f080bd5c1b2e5abb12039`
- License reported by original and conversion repositories: MIT
- [Pinned download](https://huggingface.co/CompendiumLabs/bge-small-zh-v1.5-gguf/resolve/5bf683e6a1bd454bbb60ba051088c50731d63fcb/bge-small-zh-v1.5-q8_0.gguf)

The fixture lives outside Git and outside the APK. Instrumentation verifies its
complete hash before loading. Place it in the target app's external files
directory at `embedding-test/bge-small-zh-v1.5-q8_0.gguf`. Tests explicitly skip
when this external fixture is absent; an ordinary CI build does not establish
real-model acceptance.

Run `NeuralEmbeddingRuntimeDeviceTest` using the instrumentation runner. It checks
Chinese paraphrase ranking, normalization and dimensions, independent instances,
chat-unload isolation, blank and over-window input, supplementary Unicode and
embedded NUL, concurrent close, reopen, invalid configuration, and main-thread
rejection. The six-query corpus is a smoke set, not a comprehensive semantic
retrieval benchmark or proof of multilingual quality.

### Physical-device evidence (2026-09-09)

Android 1.1.15 (901), SM-T575, the pinned external model above:

- Combined neural encoder + existing knowledge database/FTS5 suites: 21 tests
  passed in 324.748 seconds; no skipped real-model tests.
- After extending failure and hot-loop checks, the five neural tests passed
  again in 4.491 seconds. Corrupt GGUF and over-training-window load failures
  were followed by successful reopen/inference.
- Six Chinese query rankings: recall@1 6/6. Final short-query times:
  25, 21, 21, 27, 26, 28 ms.
- Next 100 short queries: P50 26 ms, P95 28 ms, P99 28 ms; P95 <500 ms gate passed.
- Reopen with the model already in the filesystem cache: 91 ms. This is not a
  reboot-cold storage/load measurement.
- Whole instrumentation process PSS at the hot-loop checkpoint: 185,793 KiB.
  This is neither the encoder-only memory cost nor a sampled peak-memory bound.
- Existing selective FTS5 test, 1,201 records: 42 ms, only one item decrypted;
  100 hot queries P50 26 ms / P95 34 ms / P99 52 ms.
- App cold activity launch after instrumentation: 2,579 ms; crash buffer empty.
- Repository checks, 73-library 16 KiB alignment gate, and 24-library QNN package
  gate passed. No real ASR/QNN inference performance benchmark was run here.

APK SHA-256:
`575ad254156e3f15497fb3ecc10a037106f46c041d6f0e6152a4bef3c4152604`.

Logs: `build/neural-embedding-device.log`,
`build/neural-embedding-final-device.log`, and logcat `NEURAL_EMBEDDING_HOT`.
Generated logs and the model fixture are not committed.

## Remaining integration

The [encrypted vector checkpoint layer](android-encrypted-vector-checkpoints.md)
adds token-aware chunking, source/model revision binding, incremental persistence,
and invalidation on source update/delete. It does not yet change production ranking.

Still provide a verified model download/lifecycle surface distinct from chat
models, background scheduling, an established vector index and hybrid retrieval,
and a learned reranker with broader recall/latency evaluation. Background and
memory-trim cleanup must cover the resulting vector cache and model lifecycle.
