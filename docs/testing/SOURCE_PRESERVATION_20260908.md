# Source Preservation Validation

## Automated Evidence

- `python -m unittest discover -s test_evolution_v2 -q`: 484 tests passed in
  759.168 seconds on Windows, including existing candidate recovery and CI ownership cases.
- `python -m unittest test_evolution_v2.test_preservation_git -v`: two additional
  Git/manager tests passed in 11.577 seconds. These verify actual immutable commits
  and durable source-contract recovery after a semantic transport failure.
- The dedicated preservation suite contains ten tests, including a sixteen-case
  before/after matrix, incomplete classifications, candidate-blind inputs, cache
  invalidation, forced review, and multi-file relocation.
- Existing literal and semantic acceptance suites also passed independently.

The main regression run observed candidate process-exit recovery at 1261 ms,
1403 ms, and 1471 ms for its controlled checkpoints. These are Desktop test-fixture
measurements, not Android reboot latency claims.

## Real Local Model Probe

A tool-free Qwen3-4B-Instruct-2507 Q8_0 model ran on a loopback-only llama.cpp CPU
server with six threads and an 8192-token context. No private goal was sent to a
cloud provider, and no real candidate or campaign was edited or published.

Four synthetic controls tested English append-only, Chinese append-only,
authorized rewrite, and adding a preface while retaining the original text.
The first prompt passed three of four: it incorrectly classified the preface as
append-only. This was a false rejection, and was not accepted as successful validation.

After clarifying the order `ORIGINAL + ADDITION` versus `ADDITION + ORIGINAL`,
all four controls passed with the production classifier and host evaluator:

| Source requirement | Classification | Prepend fixture allowed | Seconds |
| --- | --- | --- | --- |
| English append at end | append_only | No | 64.938 |
| Chinese append at end | append_only | No | 30.406 |
| Rewrite obsolete instructions | none | Yes | 26.297 |
| Add preface; retain original after it | verbatim | Yes | 33.672 |

These timings describe local background contract classification, not ordinary
chat latency. The four probes are targeted controls, not a comprehensive semantic
accuracy benchmark. A quoted source span does not prove perfect interpretation.
Broader adversarial/multilingual evaluation and the complete real-provider,
mobile-client, PR-publication and CI-repair campaign remain separate acceptance work.
