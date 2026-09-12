# GalaxySSI and Doubao Device Comparison

Date: September 12, 2026, morning, Asia/Shanghai.

## Summary

This diagnostic baseline contains nine real interactions: three unchanged questions across three entry points. Doubao was faster on all three questions and generally used a more concise consumer-oriented presentation. Both GalaxySSI entry points displayed two Dragon Ball-related images. However, Codex generated fan art instead of retrieving existing images, so that row is not an equivalent image-search speed comparison.

The main opportunities are proportional research, slow-source handling, Codex delivery latency, consistent image intent and ordering, and date-aware news/weather verification. This is not a leaderboard, a statistically representative performance gate, or a pass@1 evaluation.

## Environment and Method

| Entry point | Device | Configuration |
| --- | --- | --- |
| Doubao | S20U / SM-G9880 | 14.4.0, fast mode, deep thinking disabled; backend model not independently verified |
| GalaxySSI DeepSeek | S26U / SM-S9480 | Android 1.1.96 (982), deepseek-v4-flash |
| GalaxySSI Codex Agent | S26U / SM-S9480 and Desktop | Desktop 1.1.45, Codex Agent on DESKTOP-T14, gpt-5.6-sol, medium reasoning |

- Only S26U and S20U were operated during the baseline, not SM-T575.
- Every question started a new conversation. No extra brevity instruction, source restriction, or generation instruction was added.
- Tests ran sequentially over Wi-Fi, with system battery-saving modes disabled.
- Timing starts at the host-injected send tap. UIAutomator observations, screenshots, XML, timing samples, and GalaxySSI diagnostic logs were retained locally.
- Completion means the reply copy button appeared in Doubao, or the `已处理` status appeared in GalaxySSI. Image cases were observed for another 15 seconds.
- These are externally observed completion times, not time to first token or isolated model inference time. Polling, screenshots, and UI updates introduce sampling error.
- Hardware, application architecture, models, execution modes, and network paths differ. The results cannot isolate a model-only or hardware-only performance difference.
- A greeting warm-up and one missed send tap were excluded from the nine valid interactions.

## Observed Completion Times

| Unchanged prompt | Doubao | GalaxySSI DeepSeek | GalaxySSI Codex |
| --- | ---: | ---: | ---: |
| 广州今天的天气。 | 7.7 s | 43.9 s | 87.4 s |
| 给出2张七龙珠里的图画。 | 8.8 s | 23.5 s | 140.5 s |
| 给出今天的科技新闻。 | 18.5 s | 53.5 s | 170.2 s |

All nine interactions returned content. Returning content does not establish that every answer was correct or complete.

## Output Quality

### Guangzhou Weather

Doubao provided the date, weather, temperature, wind, air quality, a short travel suggestion, and a Moji source. DeepSeek added current conditions, apparent temperature, humidity, wind speed, today's and tomorrow's forecasts, air quality, and a table. That was substantially more work than the simple question required, with potential duplication between the summary and table. Codex answered briefly but did not include a clickable source in its final text.

Forecasts differed: Doubao reported 25-32 degrees C, DeepSeek 23-31, and Codex an afternoon maximum around 34. Location, forecast model, update time, and observation-versus-forecast definitions were not normalized, so none is treated as ground truth.

Historical spot checks during the baseline found a September 12 forecast of 25-32 degrees C and sunshine followed by thunderstorms on the NMC page, issued September 10 at 20:00. Moji showed 25-33 for September 12. These pages are mutable and the snapshots had different update times; they cannot support precise accuracy scores. Sources: [NMC](https://www.nmc.cn/publish/forecast/AGD/guangzhou.html?x=0), [Moji](https://tianqi.moji.com/tommorrow/china/guangdong/guangzhou).

Weather evidence should bind each value to a location, forecast date, observation/forecast type, and update time.

### Dragon Ball Images

| Entry point | Observed behavior | Visible output | Limitations |
| --- | --- | --- | --- |
| Doubao | Returned existing images; internal search/cache path unverified | Two related images side by side, already visible around 8.3 s | Claims about original anime provenance were not verified |
| DeepSeek | Used image search | Two related images loaded, not just links | Small vertical presentation and verbose titles; explicitly acknowledged missing individual visual verification |
| Codex | Invoked image generation twice | Two related fan-art images loaded | Wrong default intent; captions named Goku then Vegeta, while image order was reversed |

Thumbnail delivery was observed. Full-size opening and saving were not individually exercised in these nine cases and are not marked as passed.

### Today's Technology News

Doubao was easy to scan but included a stale event: the answer described Fitbit account sign-in shutdown as today's news, although Google's documentation dates that change to May 19, 2026. Historical check: [Google support](https://support.google.com/googlehealth/answer/14237024?hl=en).

DeepSeek covered many topics, linked media pages, and included verification caveats, but mixed multiple events within items and relied on aggregate news pages. A page labeled "today" is not evidence that every event occurred today.

Codex returned six mostly sourced items and distinguished a proposed negotiation from an effective policy. Recency was still inconsistent: its cited Enflame IPO report was dated September 11, not September 12. Source cited in the answer: [Reuters report via Onvista](https://www.onvista.de/news/2026/09-11-chiphersteller-enflame-zuendet-kursfeuerwerk-bei-boersendebuet-in-shanghai-0-20-26552429).

Both GalaxySSI answers discussed Habitat. The original article was dated September 11; without an exact publication timezone, that date alone does not determine whether it falls within the preceding 24 hours in Beijing. Preserve the original date. Source: [OpenAI article](https://openai.com/index/scaling-storage-one-billion-users-part-one/).

Doubao is a UX reference, not a factual answer key. These were representative historical spot checks, not exhaustive verification of every news claim. Distinguish publication time, event time, and recent background.

## Latency Diagnosis

### DeepSeek

| Task | Observed tool/model activity |
| --- | --- |
| Weather | About 34.6 s from request to completion; web_search rounds took about 6.1 s and 15.3 s, plus fetch/extract and model decisions |
| Images | Two image searches launched in the same batch took about 0.8 s and 6.0 s; another 9.4 s followed the completed searches, including model and result processing |
| News | web_research took about 30.1 s, followed by three fetches and another search; complete invocation about 48.5 s |

The slow source delayed a fast image result even though only two images were requested. The ordinary news question escalated to research and then additional retrieval. Both point to routing and evidence-sufficiency decisions, not merely final-answer length.

Example parallel context reads took tens of milliseconds. Other pre-dispatch work exists, but these observations do not establish long-term memory as the primary bottleneck.

### Codex

The weather task had a clear gap between Desktop completion and the phone's completion indicator. Desktop timestamps were compared with UI observations on the same host, not by subtracting uncalibrated phone and computer clocks.

| Milestone | Offset from send tap |
| --- | ---: |
| Desktop task created | 4.5 s |
| Desktop task started | 5.9 s |
| First body text recorded | 27.8 s |
| Desktop task completed | 53.8 s |
| Final reply queued for publication | 55.1 s |
| Phone completion observed | 87.4 s |

The gap was about 33.5 s after Desktop completion, or 32.3 s after publication queuing. The baseline alone cannot assign it specifically to the broker, publisher queue, Android consumption, or UI finalization.

The short weather answer produced 49 model updates. This motivates checking accumulated encryption, persistence, publication, and rendering work; it does not prove 49 MQTT packets were sent or that MQTT itself caused the delay.

Two serial image-generation events took about 28.6 s and 26.8 s before validation and delivery. The more fundamental issue was interpreting an existing-image request as generation. The news task spent about 158.3 s executing on Desktop, so the weather delivery gap must not be generalized to all tasks.

## Improvement Priorities

1. Instrument each run/turn through queuing, publication, broker ACK, Android receipt, decryption, persistence, and rendering. Preserve authentication, encryption, idempotency, and recovery.
2. Coalesce replaceable cumulative progress before encryption. Prioritize terminal results, fence late progress, and preserve session isolation and fair scheduling.
3. Match tool depth to task complexity, stopping redundant retrieval only when sufficient verified evidence exists. Do not impose a fixed five-second cutoff that returns incomplete evidence.
4. Treat requests for existing work's pictures as retrieval; explicit drawing, creation, and generation requests use generation. Keep captions and artifacts in one ordered structure.
5. Verify news event/publication dates and weather location/date/update time. Explain conflicts rather than arbitrarily choosing values.
6. Measure first useful output, body completion, attachment availability, task completion, and UI completion separately. An early status message is not useful answer content.

A compact image gallery is a possible future presentation improvement, not a UI change performed in this baseline.

## Follow-up Evaluation

Repeat each unchanged question at least five times, rotating entry-point order. Report medians and worst observations; do not claim a stable p95 from a tiny sample. Normalize location and date for weather, separate image retrieval from generation, and independently verify news rather than using Doubao as ground truth. Include image count, relevance, order, thumbnail, opening, and saving checks.

## Local Evidence and Scope

Ignored local directory: `build/reports/doubao-comparison-20260912/`.

- `*-r1-timing.json`: timing and UI samples for the nine valid trials.
- `*-r1-final.png` and `*-images-r1-frame-*.png`: final and intermediate screenshots.
- `results-summary.json`: summary and reduced Desktop records for the three Codex baseline tasks.
- `s26u-latency-logcat.txt` and `*-latency.jsonl`: GalaxySSI diagnostics.

The baseline phase only measured and analyzed; it did not change code, install an APK, or create a PR. Follow-up implementation is documented in [Agent Query Latency Fix](AGENT_QUERY_LATENCY_FIX_20260912.md). Cost, energy, thermals, weak networks, concurrency, and long-term stability were not evaluated here.
