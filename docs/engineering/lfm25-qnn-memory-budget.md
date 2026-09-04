# LFM2.5-2.6B QNN memory budget

GalaxySSI accepts LFM2.5-2.6B on Android only as a signed, precompiled QAIRT context deployment for the exact target SoC. Raw ONNX, QDQ, DLC, GGUF, and unprofiled packages are deliberately rejected by this path.

## Deployment contract

- Source model: `LiquidAI/LFM2.5-2.6B`
- Target: `SM8850`
- Precision: `W4A8`
- Default context: 2,048 tokens
- Maximum context: 4,096 tokens
- Runtime: precompiled QAIRT/QNN context binary
- Signed profiled process peak: at most 2.75 GiB
- Runtime process guard: 2.75 GiB
- Absolute design ceiling: 3 GiB

The 256 MiB interval between the guard and design ceiling is intentional headroom for sampling delay and small unreported native allocations. Android cannot provide a mathematical physical-memory cap for every HTP/DMA allocation, so the signed whole-process profile is the primary admission control and the runtime watchdog is a final safety boundary.

## Build pipeline

1. Export LFM2.5 with static prefill/decode graphs for 2K and 4K sequence limits. Do not compile the 128K source limit into the mobile deployment.
2. Calibrate and quantize weights to 4-bit and activations to 8-bit.
3. Use Qualcomm AI Hub Workbench or the matching QAIRT toolchain to compile and link weight-shared QNN context binaries for `SM8850`.
4. Use `qnn-context-binary-utility`/QnnSystem metadata to record spill-fill buffer size. A package without this value is incomplete.
5. Profile cold load, warm load, prefill, and decode on the target phone. `profiled_peak_bytes` must represent the complete isolated Android model process, not only the AI Hub inference-stage metric.
6. Put the context, tokenizer, templates, and runtime metadata in one directory.
7. Generate and sign `galaxyssi-qnn-deployment.json`:

```bash
node tools/models/prepare-lfm25-qnn-deployment.mjs \
  --input ./lfm25-sm8850 \
  --model-path model \
  --tokenizer-path tokenizer.json \
  --qairt-version 2.45.0.260326154327 \
  --profiled-peak-bytes 2684354560 \
  --spill-fill-buffer-bytes 268435456 \
  --certificate "$GALAXYSSI_RUNTIME_SIGNING_CERT" \
  --private-key "$GALAXYSSI_RUNTIME_SIGNING_KEY"
```

8. Zip the directory contents without adding a parent directory. Import that ZIP from **Control Center -> Local models -> Import precompiled QNN model**.

## Download publication

The Android model list includes LFM2.5 as a first-class downloadable QNN profile. Publish the same signed archive under the fixed file name `lfm2.5-2.6b-qnn-w4a8-sm8850.zip` to the GalaxySSI Hugging Face, ModelScope, and GitHub release locations used by `Lfm25QnnDownloadCatalog`.

The download service supports pause, resume, source failover, live progress, and automatic activation. It never trusts the transport alone: installation still verifies the embedded manifest signature, target chipset, W4A8 precision, process peak, spill-fill metadata, declared file set, and every file SHA-256. The manual import row remains available for offline deployment.

## Isolation guarantees

The policy is keyed only to the signed LFM deployment ID. Existing Qwen, Gemma, custom GGUF, and Whisper profiles retain their current download, memory estimation, accelerator, and lifecycle behavior. LFM inference still uses the existing `:local_model_runtime` process and is unloaded after every request, so an over-budget native graph cannot take down the UI or messaging process.

## Release evidence

Every published package must retain:

- QAIRT and QNN versions
- exact chipset and device build
- context lengths used at compile time
- precision and calibration revision
- spill-fill buffer bytes
- whole-process cold/warm peak bytes
- load time, TTFT, prefill rate, and decode rate
- numerical validation result
- file SHA-256 values and signing certificate key ID

## References

- [Qualcomm AI Hub compilation and precompiled QNN ONNX](https://dev.aihub.qualcomm.com/docs/hub/compile_examples.html)
- [Qualcomm AI Hub QNN context-binary guidance](https://dev.aihub.qualcomm.com/docs/hub/faq.html)
- [ONNX Runtime QNN context binary cache](https://onnxruntime.ai/docs/execution-providers/QNN-ExecutionProvider.html)
- [ONNX Runtime EP Context design](https://onnxruntime.ai/docs/execution-providers/EP-Context-Design.html)
- [Liquid text-model catalog](https://docs.liquid.ai/lfm/models/text-models)
