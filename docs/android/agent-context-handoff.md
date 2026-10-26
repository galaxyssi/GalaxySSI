# Agent invocation and conversation handoff

Auto selects a provider, not a replacement for that provider's saved model and
reasoning effort. Bind the per-conversation/per-target configuration when creating
the action. Explicit per-turn options win. Freeze the binding for continuation and
recovery; changing providers clears the former provider's options and binds the
new provider's configuration. Never copy Codex model IDs into a cloud fallback.
Resolve a short route alias such as `codex` to its unique paired target before
looking up configuration. A full device identity must never match a different
device merely because both end in `:codex`. If several paired devices match the
alias, final dispatch binds the selected contact rather than guessing. Freeze
the canonical identity together with model and effort in the initial plan.

The phone supervised loop carries at most 32,768 estimated conversation tokens
inside a 196,608-character prompt envelope. This is a bounded transport working
set, not the model's context window or an instruction to fill it. Short histories
remain short. The dispatch projection reserves the advertised provider's output
allowance, the actual tool/request prefix, and a safety margin before allocating
history. The wire ceiling is not a claim of a million-token active Codex window.

Legacy planning summaries remain available for local planning, but supervised
dispatch rebuilds the delivered history from encrypted source rows after routing.
It does not reuse the legacy 32K-window/70%-trigger summary as the source of truth.
The original user request and recent user changes take priority over verbose
assistant answers. Within budget they are retained without the old 16K-character
message cap. Oversized excerpts are explicitly marked incomplete with source IDs,
lengths and hashes; they are not presented as a complete semantic summary.
Measure the encoded JSON, not just the text. Never slice the JSON to fit a static
tool prefix. The source transcript remains unchanged and encrypted on disk.

`galaxyssi.phone.conversation.recall` pages earlier dialogue and reads original
content chunks. Its conversation and current-turn boundary come from the host,
not tool arguments. It rejects foreign conversations, current/future turns and
collaboration assignments (which have a separate scoped recall tool). Credential
redaction remains enabled. No whole archive is loaded to build a dispatch.

Cloud chat compaction must not truncate a prepared supervised envelope as a
single 16K-character message. A prepared envelope over the actual input budget
fails explicitly instead of silently removing history or corrupting JSON.

Provider threads remain scoped by turn for isolation. Every new turn must receive
the handoff; thread reuse is not a substitute for context delivery. A promise to
continue is not a completed answer and goes through the existing bounded repair
flow. This heuristic is not a general semantic correctness guarantee. Source
recall and the live research probe do not establish that every future research
answer will be correct, nor attest the provider's internal serving model.

Official references checked on 2026-10-26:

- [GPT-6 Astra](https://developers.openai.com/api/docs/models/gpt-6-astra):
  1,050,000 total context tokens and 128,000 maximum output. Reserving the full
  output allowance would leave 922,000 tokens for input; this is a budget
  calculation, not a guarantee about a particular Codex deployment.
- [Codex configuration](https://learn.chatgpt.com/docs/config-file/config-reference):
  `model_context_window` and `model_auto_compact_token_limit` are distinct settings;
  an unset compaction threshold uses model defaults. API capacity does not establish
  the effective Codex runtime/account limit.

Regression coverage includes Auto/manual/provider switching, long seven-turn
research histories, 2,048-32,768 token budgets, repeated summary windows, intact
handoff JSON under prefix pressure, and an opt-in public-fixture MQTT/provider
test. The live test checks preserved requirements; verify the model and effort
against the Desktop task snapshot and Codex turn context, not the model's prose.

## Device verification (2026-10-26)

The nine focused JVM suites passed all 114 tests with no failures or skips.
Both the application and instrumentation APK builds succeeded.

Android 0.1.6.28 (1404) was installed over the existing S26U installation without
clearing data. All three `AgentAutoContextHandoffDeviceTest` cases passed: saved
Auto configuration, the existing conversation's original requirements, and an
opt-in real MQTT/provider handoff containing seven generated long dialogue rounds.
The live reply preserved all six asserted requirement terms. Both the Desktop
task snapshot and Codex `turn_context` recorded `gpt-6-astra` with `high` effort.
The provider thread was `01a177ca-2174-7f81-b29d-78d0d5d0e422`; only synthetic public
dialogue was submitted in that probe. This verifies the handoff and invocation,
not the correctness of a fresh web research task or million-token operation.

### Source-backed projection follow-up

The first 0.1.6.29 build passed 119 focused JVM tests. Source paging, database
version 2-to-3 index migration, original-record reassembly and the saved settings
device checks passed on S26U. The real composer research probe then caught a
missing alias case: the planner selected `codex`, while settings were keyed by
the paired `desktop_...:codex` identity. The request still used the default model.
The alias is now canonicalized during planning and dispatch, with regressions
for ambiguity, explicit options and cross-device isolation. Final live verification
is recorded below; the first probe was not a passing result.

The long-prose summary matcher previously spent 159.371 seconds across three JVM
tests (`largeStaticPrefixCannotSliceConversationJson`,
`handoffKeepsGoalAcrossBudgetsAndChineseFollowUps` and
`formerTwoThousandTokenFallbackKeepsOriginalGoalAndRecentPairs`). Bounding path
matches and excluding prose from bare filenames reduced the same three to 0.649
seconds on the same host. The dedicated long-prose regression took 0.142 seconds.
These are context-preparation benchmark results, not provider response-time SLOs.

### Final verification on S26U

Android 0.1.6.29 (1405) was installed with data preserved. The final source passed
122 focused JVM cases and 108 broader cases (16 overlap, 214 distinct cases),
with zero failures. Three device checks passed, including the existing user
conversation's retained requirements, short-alias configuration lookup and the
isolated encrypted database migration/paging test.

The opt-in real-composer research scenario passed all four rounds in conversation
`05482539-7a8c-445e-a18c-b4799f265dea`:

1. Find two online CS/AI doctorate programs with Chinese names, tuition and official links.
2. Change the country scope to the UK while retaining the other requirements.
3. Find another program without repeating the prior results or adding conditions.
4. Restate the current requirements without browsing and identify the later changes.

All four phone turns and Desktop tasks completed. Their request snapshots and
Codex `turn_context` records consistently contained `gpt-6-astra/high`. Follow-up
handoffs contained 2, 4 and 6 complete source rows scoped to that conversation.
The final answer correctly retained the original subject, degree, online mode
and output fields, and identified the later UK-only and non-duplication changes.

Observed end-to-end round durations were 76.890, 75.306, 55.508 and 43.024 seconds.
This validates configuration and context continuity, not a latency target or
independent factual verification of every cited university fee. No million-token
runtime configuration, Desktop restart or user-data reset was performed.
