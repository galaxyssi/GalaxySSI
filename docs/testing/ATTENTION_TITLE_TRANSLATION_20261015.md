# Independent Public Headline Translation

## Scope

- Android 1.5.22 (1305), verified on Samsung S26U only.
- Feed collection continues to publish source headlines immediately. It does not wait for model translation or full-article research.
- A separate, persistent `translateTitles` preference enables lightweight translation of public `attention-feed:` English headlines for the Chinese UI. It does not enable paired/cloud autonomous research.
- Only public headlines and per-title validation feedback enter the translation request. Private conversations and article contents are not included.
- Configured, available cloud models are preferred; available local or trusted paired routes remain fallbacks. Existing concurrency, token and cost checks remain in force.
- Original headlines remain unchanged. Visible titles have priority, accepted translations are cached, and only unsuccessful entries retry.

## Reliability Changes

- Display waiting, translating, unavailable-model, capacity-wait, retry and disabled states instead of a permanent generic pending label.
- Persist in-flight leases before dispatch, preserving recovery after process interruption.
- Start failure backoff at 30 seconds and cap the delay at 15 minutes, without imposing a total retry-count limit.
- Preserve specific validation feedback, including missing Chinese text, invalid response structure and changed numbers.
- Separate replaceable timer work from KEEP-protected inference work. Scheduling another timer must not cancel the current model call.
- Treat coroutine cancellation as an interrupted request, not evidence that the provider failed.
- Preserve the continuous reader's position, expanded content and read colors when translation state changes.

## Validation

- 39 JVM tests passed: title policy (13), attention policy (12), timeline (14).
- APK and instrumentation APK builds passed.
- 15 of 16 checks passed in the final combined S26U run. Its live-network check timed out while logs showed background network constraints and interrupted work; that run is not reported as fully passing.
- A subsequent foreground recovery run passed both the real-translation check and read-only diagnostics in 17.726 seconds. Research preferences remained `paired=false`, `cloud=false`.
- Normal app execution then completed two consecutive cloud batches of 8/8 headlines in 3,905 ms and 6,742 ms. A later partial batch accepted 6/8 and retained the others for retry/fallback.
- The original diagnosis found 0 cached translations. The final read-only cache snapshot contained 181 translations. This is not a claim that every collected headline has finished translation.
- Visual inspection confirmed Chinese translated titles above their English originals, including the Mordiem and AI-engineering headlines from the real feed.
- Kotlin source-size, localization and whitespace guards passed.

## Boundaries

Translation is asynchronous and depends on an available configured model, network, Android scheduling and the existing resource budget. A translated headline is not proof that the full article was read or its claims independently verified. Existing source-verification labels remain unchanged. No Desktop upgrade or S20U installation was performed for this change.
