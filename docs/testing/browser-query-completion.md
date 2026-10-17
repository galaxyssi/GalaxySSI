# Browser Query Completion Regression

Android 1.5.56 separates completion evidence from the planner's context budget.

## Failure

A location query obtained a source page containing the answer, but the completion
gate repeatedly requested a new observation. Large supervised connector actions
consumed the 24,000-character planning-history budget before the visible ledger
filtered those actions out. Successful browser observations disappeared while
older failures remained. The completion gate then used that same lossy projection.

Browser navigation also inherited the generic mutation requirement, even though
changing the browser's current page does not establish an external business effect.

## Invariants

- Planner context budgets tool facts independently of supervised planning requests.
  Compact control markers preserve iteration counts and recovery routing, without
  repeating prompt bodies, model answers, or attachment context.
- Completion, progress validation, and recovery observation checks use the current
  plan's execution history, not `historyForReplan()`.
- Execution evidence is already stored losslessly in the encrypted active-plan
  pages. Restoring a checkpoint must not require a fresh website query solely to
  recover a receipt omitted from the model prompt.
- Conversation and turn scope apply before deduplicating action snapshots.
- New failures, pending operations, and later mutations cannot borrow old success.
- Browser create/navigate/back/close do not independently require a business
  postcondition. Their execution serialization and idempotency remain unchanged.
- Click, fill, select, dialog, unknown operations, and non-browser effects retain
  conservative verification. Explicit model-declared outcomes are still checked.
- No restaurant, address, website, or natural-language keyword is hard-coded.

## Automated Coverage

`AgentCompletionEvidenceHistoryTest` exercises oversized planner requests,
independent prompt and completion budgets, stale/failed/pending observations,
cross-conversation and cross-turn identities, browser operation semantics,
encrypted checkpoint codec recovery, and a 55-round recovery history followed by
one valid source observation. `AgentUnverifiedOutcomeRecoveryTest` also verifies
that prompt eviction does not discard origin-bound recovery evidence.
Existing outcome-freshness, artifact, publication,
prompt, history-retention, and active-plan recovery tests cover adjacent behavior.

The unit fixtures use synthetic public-page data. They do not contact websites or
prove live-provider latency. Device installation and live task continuation must
be reported separately from automated regression results.
