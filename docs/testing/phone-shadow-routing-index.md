# Phone shadow-routing index

## Cause and change

Saving one shadow-routing recommendation previously read, decrypted and sorted
the entire recommendation history to retain its newest 500 entries. This ran
synchronously on the candidate-routing path. The history is diagnostic data,
not conversation memory or a tool-call budget.

The store now maintains an encrypted timestamp/key index and atomically writes
the recommendation, index and expired-key removals. Existing databases migrate
on their first indexed access. Missing, malformed or inconsistent indexes are
rebuilt from existing encrypted records. Migration still incurs a full-history
read once; steady-state saves do not decrypt historical payloads. Reading all
history explicitly remains proportional to the requested number of records.

No routing scores, provider selection rules, ASR/QNN settings or transport
behavior were changed. A shared in-process lock protects concurrent store
instances. This does not claim cross-process writer coordination.

## Device evidence, 2026-09-09

Device: SM-T575. Android build: 1.1.33 (919). Existing app data was retained.
The opt-in instrumentation probe used the actual registered candidate inventory,
without calling any provider. Three samples were collected for each phase.

| Phase | Before | After |
| --- | --- | --- |
| Actual candidate routing | 2149.43 / 5319.34 / 2223.68 ms | 258.53 / 295.58 / 230.33 ms |
| Explicit full shadow-history read | 1594.91 / 3340.24 / 1862.11 ms | 1619.48 / 1626.08 / 2217.52 ms |

The probe reads full history before routing, so the after-routing samples exclude
the one-time migration. They are not cold-start measurements, end-to-end response
times, or P95/P99 estimates. The explicit full-history phase demonstrates why
removing that work from normal saves matters; it was not made universally fast.

Raw local logs: `build/phone-routing-shadow-baseline.log` and
`build/phone-routing-shadow-after-verified.log`. An earlier after-test attempt
used a stale instrumentation APK and failed with NoSuchMethodError; it is not
included in these measurements.

Validation:

- Full Android unit suite: 3391 tests, zero failures/errors, five skipped.
- Three device index tests passed: 520-entry encrypted legacy migration and
  retention/reopen, corrupt/inconsistent index repair, and 32 concurrent writes
  across store instances. Fixtures use separate disposable databases.
- One real-inventory routing probe passed.
- Debug application and instrumentation APK builds passed.
- Repository guard passed; 73 native libraries passed the 16 KB audit;
  QNN package audit passed with 24 libraries (221.68 MiB uncompressed).

## Real model-directed phone task

The normal App submission path sent a Chinese create/read/verify request to the
paired Codex provider. Tools executed on the phone, without a fabricated planner
response. Conversation `1940d883-eb5a-4954-86c6-7d61e07539e8`, local task
`78755900-257e-4474-9153-85d888dedec7`, token
`live-shadow-index-1788956979480` reached COMPLETED with a final assistant entry.
An independent ADB read verified the expected 56-byte file and SHA-256
`2d08a81f198607206f495cc4af9e8c9dba31b51f7ae3f14f83c0497fb59c18fc`.

Initial local planning took 416.30 ms, compared with 2410.54 ms in the preceding
1.1.32 sample. The full task took 234770 ms, measured from App task start to its
final transcript timestamp. This is NOT an end-to-end latency improvement claim:
remote inference/transport and subsequent observation remain costly. The final
UI still displayed an English tool receipt instead of a concise Chinese summary.
Both are outstanding acceptance issues outside this index patch.

Raw local evidence: `build/phone-shadow-live.json` and
`build/phone-shadow-live-spans.json`. Installed debug APK SHA-256:
`1C78B67E53765BB27076F7BF214EAF511165F5C04F23B84F941A8B7698587AC8`.
First-install time stayed at 2026-09-07 07:17:23; no app data reset was performed.

Remaining acceptance: first-access migration timing, repeated cold-start and
long-cycle measurements, and end-to-end performance/presentation improvements.
