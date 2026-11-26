# Android #3119: scoped reported usage for routing

Android reference: `e7c6af6ef3eed21c7fb697b4458d1cf742833dc4`,
`AgentResourceRouter.kt`, observed average token/cost penalties.
Source-check baseline and synchronized main: `387929097036560b483482e3590451190e7640db`,
after #4576 live adapter health merged. This PR does not repeat the merged
attribute, paired/domain or health implementations.

## Production Path

The actual cloud conversation stream engine records one valid provider-reported
usage snapshot after each completed model round, including completed tool-call
rounds. The round must have no failure, have completed, match the actual round
request ID and have valid nonnegative bounded integer counters. Cancellation,
interruption, missing/all-zero unknown usage and malformed observations do not
create a sample. No prompt-length estimator or successful-task inference is used.
Cached synthesis and legacy paths without reported usage create no sample.

The source profile and conversation eligibility are checked before streaming
and again on the main actor at commit. A record retains its source conversation
ID, exact resource ID, checked token counts, optional reported cost, time and a
hashed round identity. It contains no prompt, response, API key or raw request ID.

The store uses the existing encrypted UserDefaults helper with a profile-derived
key, a process lock and fresh read/modify/write. Duplicate round identities do
not add samples; conflicting duplicate payloads are rejected. Missing keys or
corrupt/unsupported ciphertext produce unknown metrics, not plaintext fallback
or an overwrite. There is no in-memory success publication before helper write
success. This does not promise UserDefaults fsync or storage-fault recovery.

Retention is a 30-day read window with write-time pruning and at most 1,000
records; there is no OS deletion scheduler or physical-erasure guarantee.
Mean calculation uses quotient/remainder accumulation over bounded records, not
a potentially overflowing sum. Invalid token totals are rejected as telemetry,
not as a task budget. Future timestamps are excluded.

## Selection And Source Eligibility

Main Auto selection, native preparation refresh, fresh failure ranking and
same-Desktop alternative ranking consume the snapshot. Reads require an explicit
set of currently eligible conversation IDs. Private, tracking-paused, archived,
merged, missing/deleted sources are excluded before aggregation, including
historical records whose source has since become ineligible.

Checks occur at capture, commit and read, not through a continuous privacy-epoch
observer. Existing stable-primary behavior and already recorded dispatch history
are not retrospectively rewritten when source eligibility changes.

Ranking uses Android's bounded average-token and reported-cost penalties and
economy multiplier. It does not exclude a resource on a numeric usage threshold
or restore old hard budget cutoffs. Exact resource IDs, admission, manual locks,
health/probe authority, fallback domains and effect ownership remain intact.

## Unknown Cost And Sampling Limits

The current stream usage type has no reported-cost field. Its producer therefore
records cost as nil, never an estimate, zero/free claim or price-table calculation.
Only explicit cost observations can populate the optional cost aggregate; that
schema/scoring branch has fixture coverage but no new production cost producer
in this increment. Unknown and explicitly reported zero cost remain distinct.

Statistics are per exact resource, not per selected model or endpoint revision,
matching the referenced Android resource-level aggregate. They are not complete
billing/accounting, task success, benchmark quality or end-to-end latency.
Local-model, Desktop, standalone sessions without an eligible Agent conversation,
background-budget imports, failed-round usage and broader cost producers remain
incomplete. This is not full #3119 or all-PR completion.

## Anthropic Source Correction

The existing adapter dropped start-event input counts when a later output-only
usage update arrived. It now retains only the four token fields across updates,
replaces supplied cumulative values instead of adding them, and resets at a new
message start. Complete JSON and streaming both include cache reads/writes in
total input, matching the existing native model-tool protocol convention.
These semantics follow the official [streaming](https://platform.claude.com/docs/en/build-with-claude/streaming)
and [prompt caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching) documentation.

Typed JSON counters must be nonnegative integers with checked additions.
Invalid usage is a non-authoritative marker that prevents a routing sample;
it is not a new text-delivery error or execution retry. OpenAI/Gemini parsing,
tool parsing, completion sequencing and the native model-tool protocol are
unchanged outside these declared Anthropic usage hooks.

## Verification

Ten Swift fixture methods were authored, not executed. They cover encrypted
reopen/dedup/profile/source isolation, current source eligibility, unknown cost,
large means and overflow rejection, retention/future clocks, corrupt/lost-key
containment, record bounds, real selector consumption, Anthropic cumulative
updates/cache totals and malformed counters.

Passed source-only usage, health, provider ranking, observation timing and six
context/knowledge-gap/autonomous/research/background/live-planning checks;
changed JavaScript syntax, project structure and diff whitespace are checked
separately. These do not prove Swift type correctness, crypto/security acceptance,
native delivery, continuous revocation or process-restart durability. No native
build/typecheck, XCTest, device/network acceptance, CI watching or IPA is performed.
The historical whole stable-auto checker retains its preexisting manual-selection
baseline mismatch; no full historical-check success is claimed.

```sh
node apps/ios/tools/check-routing-usage-scope.cjs
```
