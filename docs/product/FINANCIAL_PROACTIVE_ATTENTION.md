# Proactive Attention

## Entry points

- My Agent > Proactive attention configures followed public information topics.
- View discoveries opens the findings inbox. The homepage hides the entry entirely when the inbox is empty; existing read findings keep it accessible. Collection and the settings entry remain available independently.
- All, Important, Unread and Saved are inbox filters, not separate research tasks.
- Opening a finding marks that finding read and opens its existing Agent conversation for follow-up.

## Collection and delivery

Thirty-one default topics are selected initially, grouped into Finance (15), Technology and products (7), GalaxySSI (5), and Research and innovation (4). Custom topics form a separate group. Upgrading a financial-only configuration adds the sixteen new topics without resetting existing names, scopes, disabled topics, favorites, reminder mode or model permissions. Repeated loading and reconciliation do not duplicate topics or restart unchanged financial tasks.

Activating collection creates one durable continuous-monitor research task per topic. Stable task IDs prevent duplication on reopening, process recovery or repeated configuration updates. A topic can be renamed, refined, disabled or supplemented with a custom topic. Account-specific holdings remain disconnected. Adding topics does not increase model concurrency or spending budgets.

Source preferences and research questions match the topic group. Technology follows official documentation, releases, repositories and independent measurements. GalaxySSI relevance requires verified public architecture/dependency information, otherwise recommendations are labeled hypotheses. Research distinguishes preprints, peer review, replication, predictions and physical experiments; novel combinations require prior-work checks and testable hypotheses. This collects information only; it does not install software, run experiments or access private accounts.

The existing research executor collects public sources and evaluates evidence. It does not obtain brokerage access or execute financial actions. Public financial tasks do not receive unrelated personal-world or conversation context. Each result retains the source URLs, available publication dates and retrieval times.

An evidence-verified material change is persisted to the inbox independently of the existing unsolicited-message delivery budget. Notification modes are Important only (default), New findings and Collect only. Importance requires a model assessment plus verified, fresh primary evidence without contested claims; it is not inferred from a timer alone. Failed research remains visible as research status, not a fabricated finding.

Research rechecks use the existing durable scheduler, resource routing and model-call budgets. Enabling collection or changing its allowed models triggers an immediate scheduled check without the explicit-mode budget override. A model may recommend a source-dependent recheck interval; unchanged results back off. These are acquisition wakeups, not periodic notification messages. Unavailable connectivity is reported through existing tool recovery; Android background restrictions can delay a wakeup.

Paired-Agent and cloud-model permissions are scoped to attention tasks. Enabling them does not grant other global cognition jobs new model permissions. Existing resource and spending budgets remain in force.

Authorized public attention dispatches use `public-attention:<task-id>`, not the private `global-research:` transport namespace. Desktop continues to reject private global memory/evolution traffic. Evidence and synthesis replies are consumed only by the research executor with matching source ownership, conversation and turn. Public reply/receipt recovery is not blocked by the outbound authorization check.

## Small-batch news delivery

Attention now completes one active topic at a time, prioritizing captured evidence and review over opening new topics. Existing source records and checkpoints are retained. A batch collects up to two candidate news items, captures up to six original public pages through the bounded, SSRF-protected web service, and asks the model to check those captured pages and produce concise per-item summaries. Existing broad collection results can enter this review without recollection.

The model must cite exact excerpts from the captured pages. The receiver checks URLs, actual capture receipts, quote containment and date bounds. Direct official announcements can use one primary source; interpretations require independent publishers. Unsupported neighbors are omitted without blocking supported findings. This is model-assisted fact checking with program-checked provenance, not an independent factual audit or proof that every source was read completely. Captured windows expose truncation; source publication dates and model-assessed event dates must not be conflated.

The accepted summaries are rendered locally, so there is no third model call for synthesis. An empty supported set is retained as a no-news check, not published as a finding. Invalid review output receives repair feedback; exhausted review retries defer that batch rather than spin. Captured sources and review output are archived separately from the live plan.

The legacy 48-dispatch count ceiling does not govern opted-in attention. Shared token/cost budgets, concurrent-call admission, duplicate prevention and usage accounting remain intact; private background jobs retain their count setting. A legacy count-blocked checkpoint is reopened without clearing usage or evidence. Token/cost/source-read waits have explicit status text. New result callbacks wake the attention continuation and inbox delivery immediately; unrelated events no longer postpone scheduled research. Retry timers use a separate queue from new-result wakeups.

Preparation claims have process-local ownership. After process death, an orphaned claim without a dispatched model request can resume immediately without losing captured sources. Already-dispatched work retains its durable lease and receives a recovery wakeup instead of being dispatched twice. Original-page reads use the same timeout in the request and bounded transport policy; a mismatched timeout must not reject every source before network access.

Attention uses a separate high-importance Android channel and notification ID. Verified subscriptions honor the selected reminder mode rather than the unrelated unsolicited-insight scoring heuristic. Older announcements remain readable, but event dates older than two days cannot produce urgent alerts; the model must also reject expired deadlines and one-day notices as current urgency. It never launches a full-screen activity. System notification permission, channel settings and Do Not Disturb still apply. A successful system post is required before recording notification delivery. Disabling collection pauses its tasks and dismisses undelivered findings; existing saved results remain readable.

Configuration, saved flags, task checkpoints, evidence metadata and viewed receipts use the existing encrypted stores. The new screen does not introduce a separate chat, voice or model execution engine.

## Verification

Run `ProactiveAttentionPolicyTest`, `GlobalProactiveInboxTest` and `GlobalProactiveDeliveryTest` as JVM regressions. `ProactiveAttentionDeviceTest` uses isolated synthetic stores for configuration, catalog upgrade, topic lifecycle, evidence and viewed/saved state, plus the real settings screen and Android notification channel. These synthetic tests do not demonstrate real-news accuracy, relevance or long-duration background delivery.

`ProactiveAttentionLiveDeliveryTest` is opt-in (`attention_live_delivery=true`), uses the user's already-enabled subscriptions and authorized model routes, and succeeds only after a newly created real finding reaches `DELIVERED`. Its local diagnostic export contains state, counts and source receipts, not private conversation text. On SM-G9880 on 2026-10-14, a resumed batch captured two original HTML pages in 827 ms and 566 ms, obtained a paired Codex review and delivered one finding; the live test completed in 174.1 seconds. Other PDF/DNS failures did not block that supported item. This is one recovery/delivery sample, not a freshness, accuracy or p95 benchmark. The UI check exposed an older one-day announcement being marked important, so current-alert date checks were added separately.

The final v1.5.7 build passed 116 targeted JVM tests, 12 SM-G9880 device regressions and six Desktop transport-routing tests. Device regressions include subscription-mode notification admission, expired-alert suppression, the Android high-importance notification channel and recovery of abandoned preparation claims. Existing findings remained visible after the final upgrade. The real-news sample above preceded the final alert-admission adjustment; that adjustment was verified with isolated synthetic evidence rather than claiming a second live-news notification. Long-duration background reliability, broad source support and notification relevance still need larger samples.
