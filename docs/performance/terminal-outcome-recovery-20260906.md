# Desktop terminal outcome recovery verification

Date: 2026-09-06. Desktop source version: 1.0.10.
Latest main before submission: `7c059e10f`, including PR #2818. This PR contains
only Desktop/backend, test-runner and documentation changes. No Android/iOS
implementation or native ASR/QNN library is changed.

## Verified

- Initial Run Kernel/terminal archive suite: 152 tests passed in 126.133 seconds.
- Expanded final suite: 202 tests passed in 82.596 seconds. This includes the
  kernel suite plus MQTT recovery, turn routing, Codex steering, durable delivery
  and Link delivery tests. The two runs overlap and are not 354 unique tests.
- Twenty new terminal-outcome tests cover typed error/cancellation facts,
  retained original errors and partial results, malformed generations, independent
  retry bodies/receipts, page authentication across generations, Unicode large
  errors, archive write failure, committed snapshot reads, wrong scope, tombstones,
  retry races, live/uncommitted mutations and MQTT publish failure.
- The subprocess test exits with code 76 immediately after each failed/timed-out/
  cancelled task commit, before archive/event delivery. Three separate subprocesses
  are used. Reopened stores recover the original terminal error without calling
  create/resume or a provider. This is process-death evidence, not phone reboot or
  hardware power-loss durability evidence.
- Real MQTT callback integration tests verify that cancellation with an existing
  result still emits its terminal event, and that error finalization does not
  invoke artifact scans/finalization. Provider observations are injected test
  results, not live commercial-provider failures.
- Recovery metadata reads are tested with output hydration forced to fail;
  they still return the correct status/generation without populating live tasks.
- Desktop checks: 16 renderer regressions and structure checks passed.
- Repository check passed. The latest main merge changed Android/docs only;
  it did not change the tested Desktop/backend files.

Logs are retained under `build/terminal-outcome-kernel-tests.log`,
`build/terminal-outcome-expanded-tests.log` and
`build/terminal-outcome-repository-check.log`.

## Not claimed

The running Desktop was not replaced or restarted. Deployment previously met an
execution-policy rejection; no alternate deployment route was attempted. No
phone was reset, uninstalled, re-paired or operated in this Desktop-only phase.
S20U remains the default future physical test device.

Android's failed/timed-out/cancelled reply consumer, durable per-generation
acceptance, persistent page checkpoints, generation-aware task outbox retirement,
and live paired process/network chaos acceptance are still required. This is not
the complete terminal-recovery feature or completion of the larger goal. Neither
the backend test durations nor the snapshot test prove an end-to-end latency SLO.
