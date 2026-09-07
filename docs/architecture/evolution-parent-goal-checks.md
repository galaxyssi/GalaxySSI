# Parent-goal acceptance checks

Desktop 1.0.60 keeps the full original campaign objective as a required
`parent-intent` assessment. Child proposals cannot silently drop requested names,
structure, preservation, or output requirements. Missing parent text on a
campaign-owned task is incomplete evidence, not a manual-task fallback.

The shared implementation prompt also treats applicable parent requirements as
binding, rather than labeling the parent goal as context-only. Local and CLI
implementers retain requested names, structure, format and preservation even
when a child proposal omits them. Scope conflicts require replanning; this does
not authorize unrelated parent work, broader file access, or host-owned Git
publication by the implementer.

## Independent literal contract

Before semantic review, a tool-free loopback model compiles explicit literal
requirements from the original goal, scoped child task, scope, and changed paths.
It does not receive the candidate diff or file contents. This prevents the
compiler from deriving requirements by looking at what the implementation
already happens to contain.

The model returns only predicate, path, literal text, and case mode. The host
locates that literal in the original goal and attaches an exact surrounding
quote, rather than asking the model to copy or translate known source prose.
Its literal must occur within that quote, and its path must belong to the
collected candidate files. The host rejects invented literals, unsupported predicates, foreign
paths, duplicate checks, and malformed responses. Only three predicates exist:

- `contains`: required literal text is present.
- `absent`: explicitly removed literal text is absent.
- `markdown_heading`: the named top-level Markdown heading exists.

A malformed response gets one tool-free correction with its specific validation
error and unchanged original goal. Repeated invalid output is unavailable
acceptance, not a pass. Transport failures are not retried here. This bounded
protocol correction is not a cumulative implementation/action/goal budget.

If the corrected contract contains both valid and invalid checks, valid checks
can still prove a concrete candidate failure. The proof records unresolved
compiler issues alongside that failure. If all valid checks pass but any issue
remains, acceptance is unavailable; a partial contract can never authorize
publication or be reused as a complete compiled contract.

Markdown structure uses the CommonMark token parser from `markdown-it-py`, not a
line regex. Paragraph mentions, fenced/indented code, block quotes, list-nested
headings, and HTML comments do not count as top-level sections. ATX and Setext
headings, inline emphasis/code, and CRLF are supported. Case sensitivity is part
of the source-grounded contract.

The host evaluates these predicates against immutable Git candidate text. A
failure stops acceptance before the semantic reviewer can overrule it, records
an actionable parent-goal failure, and retains the isolated candidate. Passing
literal checks never replace semantic review, repository tests, or publication
gates. No shell commands, repository instructions, or remote tools execute in
this evaluator.

## Recovery and caching

Compiled contracts are stored with the acceptance proof. Their cache key covers
the original goal, child task, scope, and candidate paths. File-content changes
reuse the same contract but always re-evaluate it. Changes to those source
requirements invalidate compilation. The separate semantic proof remains bound
to the complete evidence hash, including both commits and file snapshots.

The acceptance protocol advances to v5, invalidating older passing proofs.
Explicit retained-candidate revalidation forces a fresh review. Failed checks
clear approval through the existing revalidation path; they do not delete the
candidate or publish a PR. Local inference/parser unavailability cannot pass
and does not trigger cloud fallback.

The parser is a declared backend dependency and is checked by Desktop runtime
selection, cached Windows packaging environments, and packaged smoke checks.

## Limits and validation

Source grounding proves where a literal came from, not that a small model
selected the correct predicate or extracted every semantic requirement. Empty
contracts still require full parent-intent semantic review. Nonliteral intent,
requirements on unchanged/missing files, large or binary candidates, and
multimodal acceptance still need broader evaluator coverage. This is not a
general proof of goal completion or prompt-injection immunity.

Unit tests cover source isolation, exact grounding, invalid contracts, cache
invalidation, Markdown parsing, host rejection before model review, successful
semantic continuation, and unavailable evaluators. Real retained-candidate
validation is recorded separately; synthetic passing reviewers only establish
framework behavior, not model competence.

## Real retained-candidate result

The same Chinese campaign objective and retained candidate
`0a443eb1d78891cbdd1d75f3c090c1aa9ed117d5` were revalidated using local
Qwen3-1.7B-Q8_0 on llama.cpp b10839. The candidate preserved the original guide
but appended only an unheaded sentence. No evaluator edited that document.

The earlier v4 semantic reviewer incorrectly passed every parent requirement;
only inconsistent findings prevented acceptance. Initial literal compilers then
paraphrased source quotes or invented literal variants and were rejected as
unavailable. Host-attached provenance and partial-failure evidence produced a
concrete `acceptance_review_failed`: the required literal
`Operational recovery checklist` is absent from immutable candidate text.
Approval remained cleared; the candidate and worktree were retained, not pushed.

This real model selected `contains`, not `markdown_heading`, and also proposed
two invented variants. Those unresolved issues remain in the proof. Therefore
the live result proves rejection of the missing required text, not correct
heading classification, complete requirement extraction, or a successful repair
and publication cycle. CommonMark structure checks are covered by unit tests;
real model classification and repaired-candidate acceptance remain open work.

Final local checks: 411 evolution tests, 38 focused parent/literal/acceptance
tests, 70 CLI/session/process-pool/timeline/DAG tests, 29 Desktop checks, runtime
dependency probe, JavaScript packaging syntax checks, and Repository Guard
passed. The isolated local model server was stopped after real revalidation.
No shared Desktop or phone installation was changed.

The follow-up binding implementation prompt passed 49 focused implementation,
replacement-context, literal-contract and parent-acceptance tests, including the
shared local/Codex/Hermes/Claude/OpenClaw adapter behavior. A live campaign repair
continues separately; these prompt tests do not establish model compliance.
