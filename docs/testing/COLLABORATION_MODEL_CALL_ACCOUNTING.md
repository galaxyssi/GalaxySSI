# Collaboration Cloud Call Accounting

Android v1.4.53 adds host-only, encrypted accounting for each cloud transport
dispatch made by a managed collaboration assignment. It does not change chat UI,
model selection, research limits, or the provider request body.

## Admission And Settlement

`CloudConversationStreamEngine` attaches an assignment-scoped audit sink to each
transport round, including publication repairs and streaming-to-JSON fallback.
The transport persists an admission before network I/O and one terminal receipt
in `finally`. Each dispatch receives a fresh call UUID, even when recovery reuses
the logical round ID. A terminal receipt cannot overwrite a previous terminal
outcome. Replayed identical writes are idempotent.

The ledger is scoped by group, run, turn, assignment and person. It records model
identity separately as requested and reported. It stores a request digest, not
the prompt, response text, tool arguments, endpoint, headers or API key. It is
not exposed through model recall tools or inserted into model context.

Only two bounded writes occur per dispatch, not one per output token. Group
deletion removes these receipts through the existing research archive cleanup.
Host export uses indexed pagination rather than loading the complete database.

If admission cannot persist, no provider request is sent. If settlement cannot
persist, the admission remains incomplete: the completed model operation is
**not retried** just to obtain accounting. Process death likewise leaves an
unfinished admission; reopening never turns it into a zero-cost success.

## Measurement Semantics

The first normalized schema is OpenAI-compatible Chat Completions / Responses,
including DeepSeek cache-hit fields. Counts must be nonnegative JSON integers.
Usage chunks are request snapshots, not additive deltas. Cached input and
reasoning output are subsets of input/output; they are not added again.

`tokens_complete` requires input and output counts, a valid non-overflowing sum,
an observed provider terminal, a completed dispatch, exactly one HTTP request
attempt, and no conflicting identity/count information. Conflicting aliases,
cache counts greater than input, inconsistent totals and changed response/model
identity invalidate completeness. Duplicate provider-sequence frames are ignored
before accounting, consistently with output parsing.

Missing usage is unknown. Explicitly reported zero is distinct from missing.
Partial usage can remain visible on a failed/cancelled receipt, but must not be
used as complete billing. Multiple underlying HTTP attempts (e.g. redirects or
transport retries) make whole-dispatch usage incomplete, because a final response
does not account for earlier attempts. No hidden retry cost is assumed to be zero.

Other provider schemas retain lifecycle receipts with unknown normalized usage.
No default model is substituted for a missing reported model. A reported model
label is not a guarantee that a provider's alias is an immutable model snapshot.
Cost is always `null` with `cost_status: not_measured` until a separate audited
billing or pinned rate-card mechanism supplies it.

Protocol references:
- [OpenAI streaming usage](https://developers.openai.com/api/reference/resources/chat/subresources/completions/streaming-events)
- [DeepSeek Chat Completions](https://api-docs.deepseek.com/api/create-chat-completion/)
- [DeepSeek context caching](https://api-docs.deepseek.com/guides/kv_cache/)

## Scope And Remaining Work

These receipts cover the Android collaboration cloud transport, not Desktop
Codex, the legacy standalone non-streaming client, every app model call, paid
tools, or an entire experiment. They must not be used to certify a complete
equal-budget comparison. Existing conversation usage counters remain a legacy
projection and are not substituted for this ledger.

The opt-in live evidence fixture exports the cloud receipts before cleanup,
including failed trials. Its export explicitly sets `whole_trial_complete` to
false. It neither runs automatically nor obtains additional model authorization.
No production data or manuscript belongs in this repository.

Next requirements are a whole-trial collector across Android and Desktop,
provider-specific accounting completeness, audited costs, pre-dispatch shared
budget enforcement, and independent task scoring. Unknown fields must remain
unknown while those integrations are absent.

## Verification

Local tests cover count validation, snapshot semantics, subset accounting,
missing/zero/overflow, identity conflicts, cancellation, HTTP failure, admission
failure, settlement failure, distinct retry IDs, immutable receipts, pagination,
revoked access and scope isolation. Existing streaming/cancellation regressions
must remain passing. A synthetic S26U persistence test reopens the encrypted
store; it does not call a real model or claim process-death/reboot acceptance.

```powershell
./gradlew.bat :app:testDebugUnitTest --tests '*ModelCall*' --tests '*OkHttpCloudModelStreamClientTest' --tests '*ModelStreamCancellationTest' --tests '*CloudConversationTextPolicyTest'
adb -s <authorized-device> shell am instrument -w -e class com.galaxyssi.chat.CollaborationModelCallLedgerDeviceTest com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner
```
