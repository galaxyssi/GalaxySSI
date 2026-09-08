# Retained Candidate Validation

## Scope

This is a Desktop-local framework validation with Qwen3-4B-Instruct-2507 Q8_0,
served on a literal loopback endpoint by llama.cpp b10839. Private campaign
inference did not use a cloud provider. It is not an Android device performance
measurement, a production deployment, or a claim that the overall agent goal
is complete.

The long Chinese goal asked for an English Operational Recovery section in
`docs/architecture/source-preservation-contract.md`, preserving all existing
content, modifying no other file, and publishing an English self-evolution PR.
The model-generated English child description was retained as scope context.

## Original Failure And Repair

The model had already implemented and committed the candidate. Literal
classification incorrectly translated semantic requirements into mandatory
English substrings. Host grounding rejected these invented requirements; the
correction response repeated them. No gate was relaxed to obtain a pass.

The repair separates generated scope context from the original goal and keeps
readable scope-first JSON ordering. Candidate text is never shown to the literal
compiler. Hashes still use the original canonical serializer. Unresolved
constraints, missing titles, invalid source quotes, missing semantic evidence,
and violated preservation requirements still block acceptance.

## Observed Results

- Focused literal, semantic, preservation, and immutable-Git tests: 50 passed.
- Additional prompt-boundary regression: 1 passed.
- Production compiler with the real local model: 14/14 distinct cases passed.
- Exact long campaign regression, independent uncached calls: 3/3 passed.
- Original retained candidate: literal, preservation, and semantic acceptance
  passed; all five semantic requirement IDs were assessed with no findings.
- Inference durations for that full retained-candidate run were 24.25 seconds
  for literals, 94.93 seconds for source preservation, and 409.59 seconds for
  semantic review. These are CPU-local validation timings, not chat latency.
- A fresh manager process loaded the durable accepted candidate and published
  [PR #2892](https://github.com/galaxyssi/GalaxySSI/pull/2892) through the production
  publication path. GitHub confirmed the expected branch and commit identity.
- Implementation attempts remained one. Candidate commit remained
  `013a98b5a5d2ff2aeb26bea465ee5cc283f4f6d0`: one file, five added lines, no deleted
  lines. The candidate was not manually rewritten during debugging.
- The production CI supervisor registered and observed the real PR. It reported
  `awaiting_ci`, not completion. A merge-base voice i18n failure was identified
  outside the candidate's document scope; other checks were still running at
  the time of this observation.

## Reproduction

Run from the repository root with a running loopback chat-completions provider:

```text
python tools/testing/run_literal_contract_acceptance.py --endpoint http://127.0.0.1:18572/v1/chat/completions --model qwen3-4b-validation --output build/literal-contract-live-final.json
python tools/testing/run_literal_contract_acceptance.py --endpoint http://127.0.0.1:18572/v1/chat/completions --model qwen3-4b-validation --case live_campaign_reproduction --repeat 3 --output build/literal-contract-repeated-campaign.json
```

The harness does not reuse a previous contract between invocations. It records
actual responses, failures, durations, and expected kind/path/text tuples.
Success in this finite matrix is not a guarantee across all languages or models.

The isolated run's diagnostic artifacts are retained locally under `build/`:

| Artifact | SHA-256 |
| --- | --- |
| `retained-candidate-trace.json` | `f6a71b562d76d135d2d6af8243adefed14efd307702c4e46db9346a64052fccf` |
| `literal-contract-live-final.json` | `c69df5fb286273b4b6984e6686ac5abaad828230edfa9bee878c0f1d51090af0` |
| `literal-contract-repeated-campaign.json` | `8db4e2749087d23b64a898b5008756931f8ce27a58fe00d2f70cf83afb923b95` |

## Remaining Boundaries

Publication and CI observation are verified; successful CI repair and merged
integration are separate milestones. No production scheduler was enabled and
no experimental Desktop or Android build was installed by this validation.
