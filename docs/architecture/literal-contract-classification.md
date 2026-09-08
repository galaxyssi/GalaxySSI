# Literal Requirement Classification

Status: experimental, not ready for merge or deployment. The full retained
candidate workflow has still produced invented translated constraints after the
changes below. Successful small cases and isolated replays do not establish that
the original end-to-end failure is fixed.

Desktop 1.1.2 separates examples of prescribed output wording from semantic
instructions in the candidate-blind local literal compiler. A multilingual
request to explain a behavior in English does not require a literal English
translation of every instruction to appear in the resulting file.

Generated child scope context is supplied separately, before the original goal.
It remains available to identify which parent requirements apply to the child,
but is not presented as another source of prescribed wording. Both inputs still
participate in cache invalidation. A live mixed-language task failed with the
combined input even after shorter examples passed; keeping the child context
separate corrected extraction for that exact task in a local diagnostic replay.

The model still decides which requirements prescribe exact wording. There are
no language keywords, project-specific routes, inferred pass verdicts, or
regex-based semantic classifiers. Examples cover named headings, included and
removed text, freely worded explanations, source paths, and publication steps.
Example strings do not receive special treatment: they must occur in the actual
source goal, like every other returned literal.

The host continues to ground every literal in the original goal and verify
actual immutable candidate text. Invalid translated or invented checks receive
the existing correction observation. Unresolved checks block acceptance; they
are not silently dropped. An empty literal contract does not bypass independent
semantic review or source-bound preservation checks.

The literal compiler version is 4 and candidate acceptance is
`galaxyssi.candidate-acceptance.v7`. Old compiler results, including empty results,
must be recompiled. Old full acceptance proofs cannot skip a fresh semantic
review. New inference failures never grant publication.

## Live Evaluation

Run `tools/testing/run_literal_contract_acceptance.py` with `--endpoint`,
`--model`, and `--output`. Only a literal-loopback endpoint is accepted. The
harness calls the production compiler without replacing its prompt, records
each model response, and checks exact expected kinds, paths, and text across
14 distinct cases, including the exact long mixed-language campaign regression.
The complete final 14-case matrix still requires a live run. The harness never
edits a candidate or grants goal completion.

A real campaign exposed this failure after its local model had already created
a valid append-only Git change. Its candidate was retained for revalidation,
rather than rewritten manually. Compiler accuracy is evidence for one stage,
not proof of complete autonomous development, publication, or CI repair.
