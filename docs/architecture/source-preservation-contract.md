# Source-Bound Candidate Preservation

Desktop 1.1.1 adds a candidate-blind preservation stage to autonomous candidate
acceptance. This closes a demonstrated false positive where the semantic reviewer
saw a prepended section and weakened an append-only requirement to verbatim retention.

## Flow

1. Read complete immutable base/candidate Git evidence as before.
2. Compile literal requirements without candidate contents.
3. Independently classify preservation using only original requirements, scoped
   child requirements, scope, and path identifiers. Neither file contents nor diffs,
   candidate commit IDs, implementation summaries, or review findings enter this call.
4. Persist the source contract before semantic review. Its identity includes the
   compiler version and a canonical hash of its source inputs.
5. Compare actual before/after strings at each original path. Do not trust supplied
   comparison booleans or the reviewer's natural-language preservation claims.
6. Run semantic acceptance only after these host checks pass. The reviewer may
   discover stronger requirements, but cannot weaken the bound source contract.

Modes are `append_only`, `verbatim`, `none`, and `inconclusive`. Ordinary authorized
rewrites remain valid under `none`. Empty original files still must exist when
retention is required. Moving the original text to another file does not satisfy
retention at the original path. Text comparison follows the existing Git evidence
normalization; it is not a byte-exact binary proof.

## Recovery

The acceptance proof uses `galaxyssi.candidate-acceptance.v6`. Older passing proofs
cannot bypass source classification. Candidate changes require fresh host checks
but can reuse a source contract when all source inputs are unchanged. A forced
semantic review also retains the independently compiled source contract. Transport
failure preserves the contract checkpoint without granting a passing verdict.
Changing requirements, scope, paths, or compiler version invalidates that contract.

## Limits

Source classification remains a local-model semantic judgment. Exact source quotes
prove grounding, not perfect interpretation. Ambiguous classification blocks approval
with a specific observation; it does not silently downgrade the mode. This stage
does not replace full semantic review, behavior tests, publication checks, or the
larger long-running campaign acceptance criteria. It is not a complete code-correctness
proof or a completed autonomous PR/CI repair loop.


## Operational Recovery

When the local acceptance model is temporarily unavailable, persisted source constraints are preserved to ensure continuity of source-bound preservation. Upon recovery, the system re-validates source identity using the independently compiled source contract, including the compiler version and a canonical hash of source inputs. The re-validation process triggers a re-execution of the candidate acceptance steps to ensure consistency with current requirements and evidence. Previous acceptance results do not substitute or override current validations. Any prior verdicts are treated as independent and non-binding, and the system only accepts the outcome of the re-executed validation as the current state of acceptance.