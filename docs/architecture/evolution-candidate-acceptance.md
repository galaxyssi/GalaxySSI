# Goal-aware evolution candidate acceptance

Desktop 1.0.57 adds mandatory local acceptance of isolated evolution candidates,
independently of the optional security-oriented `quality.agent_review` setting.
This is not a claim that the complete long-running Agent goal is finished.

## Execution and publication

After implementation and existing repository gates, the host creates a local
candidate commit. It collects the immutable base/candidate diff, every changed
file's before/after text, task criteria, scope, and indexed parent goal context.
The active checkout is not edited. No remote push occurs at this stage.

A tool-free loopback model reviews each criterion. The response schema requires
one keyed assessment per criterion and a preservation requirement for every
changed file. The model derives preservation intent from the task; the host
checks `verbatim` or `append_only` declarations against Git-derived text facts.
Intentional rewrites can declare `none`; this is not a blanket ban on deletions.
Text comparisons normalize CRLF to LF and do not prove byte-for-byte equivalence.

Any failed criterion or preservation check rejects the candidate. Missing
assessments, unavailable inference, or insufficient evidence cannot pass.
Semantic failures become actionable implementation observations. Existing
attempt/replanning logic can repair or explicitly replace a failed child; this
change does not introduce a cumulative goal/action budget.

Publication rechecks evidence before any push, including older pending
candidates. Cached passing assessments are bound to the contract version and
the full evidence hash, including task identity, parent intent, scope, criteria,
base commit, candidate commit, and actual file content. Changed requirements or
commits invalidate the cached result. This cache is trusted local metadata, not
a signed attestation or a proof of model correctness.

## Retained candidates

`EvolutionManager.revalidate_candidate(task_id)` checks a retained candidate
without changing or discarding its worktree. Task OS ownership and process
journal admission prevent concurrent execution/publication. The branch, HEAD,
managed worktree, and clean working tree are checked before inference.

Rejection clears its old approval and records the actual reason. A candidate
blocked solely by unavailable acceptance can be revalidated when the local
provider returns, without repeating implementation. Successful revalidation
restores readiness only while the same candidate is still eligible; it must not
resurrect cancellation. Initial execution also rechecks cancellation after the
acceptance call.

The opt-in isolated harness supports `--revalidate-task`. It never automatically
publishes a candidate. A nonzero exit for rejected/incomplete acceptance is an
expected task outcome, not a harness crash.

## Evidence boundaries

- Inference uses a literal loopback endpoint; private goal/diff data does not
  fall back to an external CLI or a cloud provider.
- Changed base/candidate blobs are bounded before reading their contents.
  The complete serialized review envelope is 128 KiB, with a 2 MB source bound.
  Exceeding either produces an explicit incomplete-evidence outcome, not a
  truncated passing review. Partitioned/larger-context review remains necessary
  for large candidates.
- Binary changes, unreadable Git objects, unsupported paths, and lossy text
  decoding require another evaluator. They are never treated as empty diffs.
- Syntax tests and static security review do not establish user-goal completion.
  Conversely, model acceptance does not replace execution tests or security
  review. A small model can still misinterpret requirements; broader semantic
  evaluation and stronger independent evaluators remain required.
- Repository/model text is untrusted evidence. It is not executed by this
  evaluator. This does not claim prompt-injection immunity.

## Validation

Focused tests use real temporary Git repositories for failure-feedback retries,
immutable snapshots, legacy publication rejection before push, cached-proof
invalidation, candidate-preserving revalidation, unavailable-provider recovery,
and cancellation. Controlled model fixtures explicitly test framework behavior;
they do not establish model competence.

The retained real Qwen3-1.7B candidate from the read-revision acceptance test is
also used as a negative case: it replaced a 56-line document with a three-line
checklist despite the instruction to preserve the original and append. It was
not published. The first local semantic response omitted criteria; a second
diff-only response incorrectly asserted preservation. These failures motivated
required keyed assessments, full file snapshots, and host-checked preservation.

With the final response contract, the same real model still claimed the old text
was preserved, but declared a `verbatim` preservation requirement. The host's
immutable comparison rejected that claim with `acceptance_review_failed`, cleared
approval, and preserved commit `5b3ea9cbcba7f14e446122dbe253b9a6c3dd3b4b` and its
worktree. This establishes rejection of this real false-positive case, not
general semantic correctness of Qwen3-1.7B. The model could still misclassify the
required preservation mode itself. A complete repaired-candidate/publication/CI
cycle and broader requirement-evaluator coverage remain to be verified.

Local regression results for this change: 362 evolution tests, 70 CLI/session/
process-pool/timeline/DAG tests, 29 Desktop checks, and Repository Guard passed.
The final response-contract suite also passed independently (11 tests). No
Android runtime, ASR/QNN configuration, shared Desktop process, or phone data was
changed by this isolated validation.
