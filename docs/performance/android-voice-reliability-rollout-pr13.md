# Android Voice Reliability and Rollout

PR-13 adds a shared reliability boundary around the low-latency voice pipeline. It keeps resource decisions, failure isolation, performance evidence, and staged rollout separate from transcript and task content.

## Runtime admission

Every governed workload declares whether it needs local inference, network access, foreground execution, reduced concurrency, and a measured or estimated peak PSS. Admission combines:

- `ActivityManager.MemoryInfo`, current PSS, certified peak PSS, other local-model use, and a dynamic safety margin;
- Android thermal status with cooldown hysteresis;
- battery, foreground, and network constraints;
- a feature/profile-scoped circuit breaker;
- a stable per-install rollout cohort and hard privacy, security, diagnostics, and certification gates.

Moderate heat reduces Partial frequency. Severe heat disables Second Pass, limits threads, and asks the runtime to release large models. Critical heat, shutdown, low-memory signals, unsafe memory headroom, or a critical unplugged battery block local inference. A lower thermal observation does not immediately reload a large model because the previous pressure remains held through a cooldown window.

## Circuit breaker

Circuits are isolated by feature and model profile. One OOM or model verification failure opens the affected circuit immediately. Native crashes, persistent thermal pressure, timeouts, provider protocol failures, TTS underruns, and Agent delta failures use bounded thresholds. User cancellation never counts as a failure.

After cooldown, only one half-open probe may run. Success closes the circuit; failure reopens it. App/profile generation changes clear stale circuit state, while ordinary restarts preserve it. This prevents unlimited automatic retries and leaves unrelated providers and models available.

## Rollout and rollback

The policy models developer, internal, opt-in beta, stable cohort, certified expansion, and default-with-fallback stages. Stable stages require sufficient samples, multiple stable releases, no crash or ANR regression, meaningful p95 improvement, reliable fallback, reviewed privacy/security, diagnostics, and support documentation. Local realtime inference also requires device certification.

Rollout is independent per feature. A failed feature rolls back only that optimization; local realtime Whisper falls back to Final-only. User privacy choices and downloaded models are never changed by rollback.

The gate is controlled by `voice.reliability_governor_v1`. It defaults on only for debuggable builds and remains opt-in for release builds.

## Performance dashboard contract

The content-free dashboard snapshot exposes:

- session success, failure, and fallback rates;
- p50 and p95 for ASR, model, TTS, and Agent milestones;
- OOM, native crash, and thermal downgrade counts;
- current resource mode and reasons;
- open circuits and per-feature rollout decisions.

No transcript, prompt, model response, file path, credential, or raw audio is included.

## Focused verification

Unit coverage includes certified memory gates, low-memory signals, battery and network restrictions, thermal cooldown, half-open concurrency, OOM/native/timeout thresholds, generation reset, cohort stability, rollout quality gates, dashboard health, and deterministic 10,000-transition stress simulations.
