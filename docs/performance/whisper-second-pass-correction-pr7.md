# Whisper Second Pass and Correction Safety

This change implements the two-pass transcription safety contract from the deep latency optimization specification.

## Runtime flow

1. A certified fast model produces the only transcript eligible for initial routing.
2. Conversation and low-risk requests may dispatch once immediately.
3. A policy-approved accurate model may decode the same frozen PCM snapshot in the background.
4. The correction controller compares normalized text and protected entities.
5. Corrections can update display state and future context, but never invoke the original callback again.
6. High- and critical-risk speech waits for the accuracy pass when one is certified, then requires explicit confirmation before the first dispatch.

Starting a new voice capture cancels benchmark work and all ordinary second-pass work, then aborts the active native decoder. Medium and large models are therefore never selected outside the device-certified policy.

## Protected entities

The consistency checker compares:

- recipients;
- phone numbers;
- amounts and currencies;
- dates and times;
- file paths;
- applications;
- devices;
- negation;
- send, delete, overwrite, payment, call, install, and publish actions.

A protected mismatch blocks high-risk execution and presents both transcripts to the user.

## Idempotency and privacy

`VoiceExecutionLedger` limits primary dispatch, external side effects, Agent runs, and correction TTS announcements to one per voice session. The bounded ledger persists only a SHA-256 hash of the fast transcript, not its plaintext.

Material corrections are stored in encrypted app-private storage with model profile, model SHA-256, execution mode, revision, and completion time. PCM is copied only for the active accuracy pass, zeroed on completion or cancellation, and never persisted.

Correction context is appended as historical metadata to a later Agent turn. It is explicitly marked as non-executable and cannot cause the original model, tool, message, file action, or Agent run to repeat.

## Feature flag

The implementation is controlled by `voice.whisper_second_pass_v1`. Debug builds enable it by default; release builds remain opt-in until staged rollout completes.

## Verification

Focused tests cover:

- recipient and file-path mismatches;
- all five risk levels;
- user-edit precedence;
- punctuation-only changes;
- stale and duplicate correction revisions;
- one primary dispatch, external side effect, Agent run, and correction announcement;
- new-voice preemption;
- duplicate second-pass scheduling;
- high-risk accuracy work even when the user selected Fast mode.

Validated on 2026-08-01 with:

- 1,246 Android JVM tests: 0 failures, 0 errors, 1 intentional skip;
- the Android repository and APK build gates;
- one focused instrumentation test on a Samsung SM-T575 running Android 13;
- encrypted-store recreation, duplicate-dispatch rejection, and plaintext-at-rest checks.
