# Proactive Attention

## Entry points

- My Agent > Proactive attention configures followed public information topics.
- View discoveries opens the findings inbox; the homepage keeps a discoveries entry visible even with no unread findings.
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

## Notifications and recovery

Attention uses a separate high-importance Android channel and notification ID. It never launches a full-screen activity. System notification permission, channel settings and Do Not Disturb still apply. A successful system post is required before recording notification delivery. Disabling collection pauses its tasks and dismisses undelivered findings; existing saved results remain readable.

Configuration, saved flags, task checkpoints, evidence metadata and viewed receipts use the existing encrypted stores. The new screen does not introduce a separate chat, voice or model execution engine.

## Verification

Run `ProactiveAttentionPolicyTest`, `GlobalProactiveInboxTest` and `GlobalProactiveDeliveryTest` as JVM regressions. `ProactiveAttentionDeviceTest` uses isolated synthetic stores for configuration, catalog upgrade, topic lifecycle, evidence and viewed/saved state, plus the real settings screen and Android notification channel. These synthetic tests do not demonstrate real-news accuracy, relevance or long-duration background delivery.
