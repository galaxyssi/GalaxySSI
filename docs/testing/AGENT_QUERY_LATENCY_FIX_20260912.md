# Agent Query Latency and Image Delivery Fix

Date: September 12, 2026. Baseline: [Doubao comparison](DOUBAO_COMPARISON_20260912.md).

## Scope and Versions

- Development started from main `22b632a09` on `fix/agent-query-latency-and-media-intent-20260912`.
- Device-tested versions: Android 1.1.98 (984), Desktop 1.1.47. The first Codex retest used Android 1.1.96 with the updated Desktop; DeepSeek retests followed installation of 1.1.98.
- PR preparation integrates main `0eb47b7ef` and advances Android to 1.1.100 (986), above upstream 1.1.99 (985). Desktop remains 1.1.47. Device timings below belong to the earlier tested builds, not a claimed retest of 986.
- Only S26U / SM-S9480 was operated during the implementation retests, not S20U or SM-T575. Installation preserved existing app data.
- Questions, models, and reasoning settings were unchanged, with a fresh conversation each time. No extra instruction forced short answers.
- Timings run from the send tap to the localized processed status, not first token. Image cases include another 15 seconds of observation.
- r2 contains one trial per combination, followed by targeted r3-r5 diagnostics. Network, caches, output length, and paths vary; this is not a statistical performance gate.

## Changes

1. Isolate a progress credit window per paired route, with at most two unacknowledged running-progress packets. Credit is released only on the authenticated application delivery-ACK path after Signal decryption; broker PUBACK is not proof of phone consumption.
2. When credit is exhausted, retain each task's latest plaintext snapshot before encryption. The existing retry worker delivers it later. Terminal, approval, paused, and waiting-for-input events bypass the progress window.
3. Read the real `task_status` wire field for delivery priority, retaining the `status` fallback. Final results keep their reliable outbox and priority path.
4. Recover credit after a 30-second lost-receipt lease and bound route bookkeeping. This is flow-control recovery, not a model execution deadline or concurrency limit.
5. Preserve Signal, outer MQTT encryption, padding, durable final results, replay protection, and execution-generation checks. Do not delete or reorder already encrypted or transmitted packets.
6. Add Android debug-only queue, decryption, dispatch, and total handling timings without message bodies.
7. Honor image result counts from 1 to 12, defaulting to 3 instead of forcing at least 6. Unplanned research defaults to fast mode with three evidence items; explicit profiles and query plans remain intact.
8. Make ordinary weather/news queries proportional to the request and stop redundant research once evidence is sufficient. Distinguish existing-image retrieval from explicit original creation. Preserve failure disclosure and source validation.
9. Order generated images by creation order and delivered attachments by final Markdown reference order, not hash filenames or directory traversal.
10. Require date/location-aware weather sources and distinguish news event time, publication time, retrieval time, and timezone. Discourage unrequested multi-day tables, duplicate captions, and unverified image names.
11. Parse `[![image](image-url)](source-url)` as a complete linked image, preventing a leftover `](url)` wrapper. Streaming previews retain one valid source link. Ordinary links and code examples remain unchanged.
12. Bind local image alt text to its image card and normalize paths to the current task. Only validated image outputs from that task are eligible; input attachments and cross-task files are excluded. Preserve original image bytes.
13. Reduce the shared model client's idle connection retention from five minutes to one minute and add 20-second HTTP/2 pings. Preserve active stream read/call timeout behavior; do not retry side-effecting tools to resolve a stalled connection.

## r2 Retest

| Entry | Question (English translation) | Baseline | r2 |
| --- | --- | ---: | ---: |
| DeepSeek | Today's weather in Guangzhou. | 43.9 s | 25.1 s |
| DeepSeek | Show two pictures from Dragon Ball. | 23.5 s | 10.7 s |
| DeepSeek | Give today's technology news. | 53.5 s | 37.9 s |
| Codex | Today's weather in Guangzhou. | 87.4 s | 51.9 s |
| Codex | Show two pictures from Dragon Ball. | 140.5 s | 67.8 s |
| Codex | Give today's technology news. | 170.2 s | 99.6 s |

Codex mistakenly generated two original images in the baseline and retrieved existing images in r2. That row demonstrates corrected task behavior, not faster execution of the same generation tool.

The Codex weather Desktop-complete-to-phone-complete gap fell from about 33.5 s to 3.2 s. r2 image and news gaps were 9.7 s and 5.5 s. These comparisons use Desktop timestamps and UI observations from the same host, not uncalibrated clocks on two devices.

Baseline diagnostics also showed broker PUBACK about 0.38 s after final publication, while phone uplink ACKs sometimes waited over 20 seconds and caused reconnects. Phone decryption/dispatch after receipt usually took tens of milliseconds. The 49 model updates and roughly 21.9 KB padded wire packets indicated backlog risk, not proof that 49 packets were published.

DeepSeek r2 used one weather search/fetch sequence with search around 6.1 s, one image search around 0.76 s, and several news searches/fetches without web_research. One news search tail still took about 13 s.

## Additional Retests and Counterexamples

| Entry | Case | Observation |
| --- | --- | --- |
| DeepSeek | Weather r3 | Final reply controls appeared around 29.5 s; UI recorded the localized processed status with a 28-second duration. A long answer scrolled the terminal indicator offscreen, causing the old script to report a false 180 s timeout. Scrolling back verified completion; this is not an app timeout. |
| DeepSeek | Images r3 | No response within the 180 s measurement window. The initial HTTP request wrote its body but received no response headers and never started image search. The trial was explicitly cancelled around 215 s. |
| DeepSeek | Images r4, after connection fix | Completed in 7.07 s with two relevant images visible. Image search took 793 ms without a search-cache hit. Fresh connection: DNS 18 ms, connect 63 ms including TLS 36 ms, header wait 131 ms. The following model round successfully reused the connection. |
| DeepSeek | News r3, after connection fix | After about three minutes idle, a fresh connection took DNS 20 ms, connect 46 ms including TLS 23 ms, header wait 171 ms. Total remained 59.55 s; news latency is not consistently improved. |
| Codex | Images r3 | 100.10 s total. Host offsets: Desktop receipt 32.92 s, model complete 73.02 s, remote images prepared 88.59 s, reply queued 90.90 s. Linked-image wrapper residue was found and subsequently fixed. |
| Codex | Images r4 | 84.16 s total, 3.51 s from Desktop completion to UI completion. Both images loaded, but local alt text became a duplicate title list; subsequently fixed. |
| Codex | Images r5 | 50.67 s total. Captions appeared on the corresponding cards with no extra title list or path text. Both images were visible; frame inspection confirmed the first was a working animated GIF rather than a loading failure. Model-complete-to-UI gap was 10.39 s, including about 5.8 s of image preparation. |

The stalled DeepSeek image request reused a connection idle for about four minutes: `connection_reused=1`, `request_write_ms=1`, `response_headers_wait_ms=-1`, and about 214.8 s before cancellation. This locates the wait before response headers, but does not prove whether NAT, carrier networking, or the provider caused it. Shorter idle retention and HTTP/2 health checks mitigate that failure mode; more weak-network and long-idle tests are needed to establish reliability.

The later news request still reached model round 6. Round 5 carried approximately 84,396 JSON characters, including 59,582 characters of tool results; about 10.9 s of generation was followed by citation repair. Task-aware evidence sufficiency, evidence compaction, and repair-reason classification remain follow-up work. Skipping citation checks or forcing an early incomplete answer is not an acceptable performance fix.

The harness was also corrected for model-picker scrolling/waits and offscreen completion indicators. Unconfirmed picker attempts did not submit prompts and are excluded from model timings. Historical raw timing files were not overwritten; the weather r3 correction is explicitly reported above.

## Quality and Limitations

- Both Codex r2 retrieved images displayed in caption order without original generation.
- Both DeepSeek r2 images displayed, but a source title introduced a character-naming risk. Search titles alone do not establish visual verification.
- Codex r2 weather included a clickable source; news included dates and identified some events as September 11.
- DeepSeek r2 weather still included unrequested multi-day information and repeated tables. Output policy was tightened afterward.
- Date and naming policies guide model behavior; they do not guarantee factual accuracy. Every weather value, news fact, and original-art claim was not independently verified.
- Full-size opening and saving were not comprehensively retested in this latency run.
- Codex news execution still took about 90 s in r2, and DeepSeek news retained slow search tails. These changes do not establish Doubao-level speed for all tasks or eliminate network variance.
- Cost, energy, thermals, long-term reliability, and real high-concurrency model execution were not evaluated.

## Regression Coverage

Before integrating the subsequent main changes:

- Desktop: 164 tests passed, covering route isolation, ACK windows, lost-receipt recovery, 1,000 concurrent credit requests, latest-snapshot replacement, terminal cleanup/priority, encryption failure recovery, artifact ordering, result outbox, linked-image Markdown, local captions, and cross-task isolation. The credit-request test is not 1,000 real model tasks.
- Android: 48 tests passed across `AgentPublicImageSearchTest`, `CloudWebGroundingTest`, `AgentPublicWebSearchParserTest`, and `OkHttpCloudModelStreamClientTest`, including connection reuse, ping configuration, cancellation, and preserved long-running timeouts.
- Android debug APK assembly, the 150 KB Kotlin source-size gate, and `git diff --check` passed.
- Android 1.1.98 (984) was installed on S26U and Desktop 1.1.47 restarted from this worktree. User data was not cleared.

After integrating main `0eb47b7ef`, the same 164 Desktop backend tests and 48 Android tests passed again. `npm --prefix apps/desktop run check` passed 29 tests and the Desktop structural check. `npm run check` and `git diff --check` also passed.

The first integrated Android build could not locate Rust. Setting `CARGO_HOME` and `RUSTUP_HOME` to the existing local toolchain cache resolved the environment issue without source changes or skipping native packaging. Rust native-memory compilation and 16 KiB ELF alignment checks passed, followed by `:app:assembleDebug`. APK metadata confirms Android 1.1.100 (986); Desktop package and lockfile both specify 1.1.47.

The version 986 APK was built but not newly installed or device-benchmarked during PR preparation. Broad device and packaged Desktop smoke matrices were not rerun; the device evidence above remains associated with the earlier tested builds.

Raw screenshots, XML, polling samples, and logs remain in the ignored local directory `build/reports/doubao-comparison-20260912/`; they are not committed.

## Follow-up Acceptance

Repeat the same tasks across multiple runs and weak-network/lost-ACK conditions. Track first useful output, first visible image, complete delivery, p50, and p95 with sufficient samples. Continue reducing news retrieval tails while independently checking sources; shorter answers alone do not demonstrate better accuracy.
