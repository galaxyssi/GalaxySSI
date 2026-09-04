# GalaxySSI iOS

GalaxySSI iOS is a native SwiftUI client for iOS 15 and later. It mirrors the Android client's primary mobile surface: chats, contacts, GalaxySSI Link pairing, direct cloud model contacts, voice capture settings, local notifications, and durable local state.

## Current Scope

- SwiftUI app target and XCTest target in `GalaxySSI.xcodeproj`
- Chats and contacts backed by a local Codable store, including searchable chat/contact lists, unread conversation summaries, local message deletion, chat history clearing, message details, and delivery trace inspection
- Android-style encrypted Agent transcript persistence with deferred content chunks, Keychain-held per-store keys, and legacy UserDefaults migration
- Android-style encrypted local state persistence for chats, contacts, pairing links, Agent settings, and durable task metadata, with Keychain-held AES-GCM keys and one-time migration from the legacy UserDefaults state
- Android-compatible GalaxySSI Link v1 QR validation, route generation, pairing claim encryption, envelope creation, and envelope validation
- Native MQTT 3.1.1 transport over TLS for pairing topics, Link topics, and background message delivery handoff
- Durable Link outbox, exponential retry, delivery acknowledgements, Android-style delivery trace stages, inbound dedupe, and Android-compatible `signal-chunk` MQTT payload chunking
- Android-style MQTT publish result acceptance, reconnect backoff, and relationship subscription recovery policies
- Android-style Link transport diagnostics for encrypted replay, pending replay, duplicates, old counters, decrypt failures, and fragment rejection events with anonymous endpoint/message references and a Settings summary/recent-events view
- Android-compatible unified command payloads for desktop MQTT commands and structured command results
- Android-compatible `galaxyssi_contact` QR export/import with pending friend requests, approve/reject handling, and verified contact creation
- Local contact management with Android-style remark rename, soft delete, optional chat deletion, and private data reset
- Explicit file/photo attachments with Android-compatible descriptors, inline `data_b64` transport for small payloads, metadata-only fallback for larger files, and chat composer previews
- Android-style weak-network media delivery profiles for normal, constrained, and offline links, including compact image/audio targets, media payload profile metadata, and validated-network outbox gates for deferred media
- Android-style iOS device profile policy for phone, tablet, CarPlay/automotive, and legacy or low-memory iOS devices, including read/team/QEMU budgets, capture downscaling, input target hints, reduce-motion flags, and conservative media adaptation
- Android-style attachment workspace staging into app-private agent-native workspaces with safe names, per-turn limits, SHA-256 metadata, and stable workspace IDs
- Android-style animated image timing normalization for zero-delay GIF frames
- Direct cloud model contacts for OpenAI-compatible, Anthropic, and Gemini-style APIs, with provider-level model selection, readiness checks, and API keys stored in Keychain
- Android-style cloud context overflow detection for cloud model retries and clear request-size failures
- Android-style connector availability policy for desktop agent heartbeat freshness and auto-routable cloud model readiness
- Android-style language policy settings for interface preference, model response language, ASR locale, and TTS language
- Android-style app display text sizing with System, Standard, Comfortable, Large, and Extra Large modes
- Android-style Agent Safety settings for task execution mode, action permission mode, safety guards, pause state, and allowed action surfaces
- Android-style Agent task execution mode policy for plan-only and auto-complete request signals
- Android-style Agent execution location and runtime presentation for phone, phone Linux, cloud API, desktop Agent/tool, connected device, and knowledge routes, including durable task record identity fields
- Android-style Agent confirmation policy for Direct, Confirm Once, and Confirm Always action gating
- Android-style Agent plan editor for updating, removing, and moving pending actions with dependency protection, input-key mapping, revision bumps, and validation refresh
- Android-style Agent tool coordination for dependency/output-source parsing, graph remapping, next-runnable selection, failed-dependency blocking, output handoff materialization, and tool graph depth checks
- Android-style agent permission grant ledger for scoped host grants, single-use consumption, expiry, revocation, and JSON snapshots
- Android-compatible remote agent approval request parsing and approval/denial decision payloads
- Android-compatible remote reputation execution receipts and independent attestations with canonical payload hashes and desktop/agent/task binding checks
- Android-style agent reputation snapshot scoring for reliability, quality, timeliness, cost efficiency, verification confidence, and routing adjustment
- Android-style agent network search for capability-aware ranking, trust/cost/capacity filters, reputation routing weight, stale heartbeat handling, and revision-safe pagination
- Android-style dynamic agent team compilation for lead/specialist/verifier assignment, pinned identities, failure-domain diversity, trust/budget boundaries, and team definition DAGs
- Android-style agent team plan bridge for supervised team dispatch specs, synthetic team actions, dependency remapping, retry rekeying, and dynamic team expansion
- Android-style managed team response delivery for exactly-once connector replies, late response correlation, durable response codecs, and completion dedupe ledgers
- Android-style cross-team delegation for minimal disclosure envelopes, policy firewall admission, immutable destination review, isolated run requests, and Android wire-compatible receipts
- Android-style connector response bus for managed response interception, late ledger completion, rich-output fallback text, listener fanout, and bounded pending response storage
- Android-style execution presentation policy for phone, desktop, cloud, and connected-device task locations
- Android-style remote task status policy for terminal-without-response settlement, health-preserving remote statuses, visible phase/workspace mapping, timeout metadata, and restored-task deadline budgeting
- Android-style iOS Agent control-plane terminal status settlement for failed, cancelled, timed-out, and missing remote connector tasks without waiting for a final response
- Android-style iOS connector task status recording for accepted, queued, running, waiting, completed, and terminal remote task progress without ending active waits
- Android-style iOS connector transport accepted receipts for preserving active waits and recording transport handoff timing
- Android-style iOS connector timeout resolution for failover-aware accepted/running/read-only stale waits with Android-compatible timeout metadata
- Android-style iOS connector steered result acceptance for merged remote task updates with disposition metadata and timeout cleanup
- Android-style iOS task watchdog timeout results for active Agent runs with `TASK_WATCHDOG` metadata and terminal remote status projection
- Android-style connector failover and timing policy for desktop fallback, transport queues, read-only stale execution, and attachment deadlines
- Android-style cron expression parser for workflow schedules with time-zone aware next/previous matching
- Android-style proactive task policy for interval/cron misfires, deterministic jitter, goal checkpoints, team validation, and run outcome limits
- Android-style global proactive inbox for delivered findings, digest grouping, feedback filtering, and viewed-state projection
- Android-style Agent Memory models and local store behavior for Android wire-compatible memory items, snapshots, command parsing, duplicate consolidation, key-scoped conflicts, conflict resolution, lineage deletion, importance sorting, recall scoring, and conversation scope rebinding
- Android-style Global Memory temporal and query foundation for world items, memory inbox candidates, namespace isolation, temporal snapshots, evidence refs, cross-conversation relevance, query classification, preferred namespaces, relation hints, and Android wire-compatible memory state payloads
- Android-style inline Markdown parsing for bold, italic, strike, code, and link segments
- Android-style transcript scroll policy for auto-follow and older-history pagination thresholds
- Android-style transcript lifecycle policy for legacy planner cleanup and stale connector recovery
- Android-style transcript presentation and render diff policy for stable grouped process progress rows
- Android-style task liveness transcript policy for watchdog warning, recovery cleanup, timeout replies, and terminal-reply suppression
- Android-style task liveness transcript reducer for applying watchdog upsert, append, and delete operations with dedupe semantics
- Android-style task liveness signal action policy for pending connector consumption, recoverable run reconciliation, active timeout cleanup, and watchdog timeout forcing
- Android-style task liveness workspace reducer for sweep-time stalled/timed-out event projection, progress recovery signals, heartbeat throttling, and bounded event journals
- Android-style task workspace control reducer for cancellation transitions, permission-revocation pauses, execution cancellation intents, and bounded event journals
- Android-style process-lifetime task supervisor for read-reasoning and side-effect lanes, foreground leases, cancellation checkpoints, durable resume hooks, watchdog sweeps, and late connector recovery
- Android-style Agent workspace runtime metadata for parent/Agent/device/run identities, delivery mode, snapshots, permissions, handoffs, tool calls, checkpoints, artifacts, and Android store timestamp compatibility
- Android-style late connector response reconciliation for authenticated remote results that arrive after local timeout and are bound to the original handoff
- Android-style Agent workspace execution snapshot reducer for status projection, plan/result/error retention, tool call/artifact ledgers, permission and handoff merging, and remote sequence advancement
- Android-style Agent workspace checkpoint reducer for checkpoint events, plan/state snapshots, same-id replacement, ordered retention, and Android's 10-checkpoint bound
- Android-style Agent workspace bounds policy for Android-matched workspace, event, tool-call, checkpoint, artifact, permission, and handoff normalization limits
- Android-style agent task identity generation and desktop response matching
- Android-style agent task intent classification for chat, code, phone, desktop, research, file, memory, and automation requests
- Android-style agent execution profiles for task kind, timeout, artifact, installation, and verification contracts
- Android-style runtime pack catalog for signed runtime pack metadata, dependency validation, compatibility filtering, install receipts, and China release mirrors
- Android-style embedded runtime bootstrap index validation for bundled linux-base and python-uv packs with dependency, SHA-256, size, and downgrade guards
- Android-style local model runtime preflight for Gemma/Qwen profile selection, model-file launch gates, memory/KV-cache budgeting, thread reduction, iOS thermal status, battery, and Low Power Mode readiness decisions
- Android-style iOS local model accelerator capability detection for CPU, Metal GPU, Core ML Neural Engine, and vendor SDK readiness with hardware-only honesty when the matching runtime adapter is not bundled
- Android-style runtime capability matrix for native tools, system tools, connector targets, setup states, and blocked executability
- Android-style native tool result receipts and replay store for idempotency-key reuse, Android wire-compatible replay snapshots, success-only durable caching, and retention pruning
- Android-style capability catalog for native tools, MCP connections, automation marketplace state, permission diffs, dynamic authentication, and dependency readiness
- Android-style Local MCP runtime bridge response codec for structured tool/list/call results without leaking process logs
- Android-style MCP package manifest codec for declarative HTTP and sandboxed local stdio packages with auth, tool, timeout, endpoint, and local-runtime guard validation
- Android-style MCP package archive inspection for signed and unsigned local packages with manifest digest checks, safe ZIP entry validation, stored and deflated ZIP entry extraction, and runtime entrypoint enforcement
- Android-style MCP package repository and registry installation for durable local package metadata, runtime workspace preparation, request cleanup, package SHA/version tracking, and local-package connection projection
- Android-style Local MCP runtime client for list/call invocation payloads, secret environment rendering, bridge response decoding, request cleanup, and native tool result mapping
- Android-style declarative HTTP MCP client for manifest-backed tools with same-origin URL resolution, args/auth template rendering, bounded response parsing, JSON-path result selection, and HTTP auth failure handling
- Android-style MCP authentication exchange coordinator for manifest-backed sign-in and refresh flows with field/auth template rendering, same-origin enforcement, accepted-status checks, and response-to-secret mappings
- Android-style Streamable HTTP MCP transport for JSON-RPC POST, SSE data event parsing, protocol/session headers, unsafe-header filtering, and HTTP authentication failure surfacing
- Android-style remote MCP session client for initialize negotiation, initialized notifications, server notifications, ping and method-not-found responses, tools/list pagination, tools/call result parsing, resources/list and resources/read, prompts/list and prompts/get, JSON-RPC error mapping, and capability gating
- Android-style MCP client manager for registry-backed list/call routing across declarative HTTP, local stdio, and Streamable HTTP transports with security decisions, audit metadata, session caching, and authentication failure handling
- Android-style agent plan lifecycle policy for stale runtime draft cleanup and completed connector restoration
- Android-style agent execution continuity for pre-action checkpoints, Android screen digests, rollback actions, interrupted action recovery, and bounded replan history
- Android-style agent execution loop timeline policy for run-control events, recovery actions, and progress placeholders
- Android-style agent run recovery policy for terminal run-state reduction, local wait restore, and durable desktop reconnects
- Android-style agent run start receipts for cross-end idempotency keys, durable accepted handles, unknown outcomes, cancellation marking, and bounded snapshots
- Android-style Agent control plane protocol negotiation, control messages, recoverable run handles, registration provider profiles, and cross-Agent handoff ledger recovery
- Android-style Agent control plane transport-backed adapters, providers, network directory search, and team coordinator startup routing
- Android-style Agent control plane action executor bridge for connector actions, stable run IDs, delivery modes, prepared dispatch receipts, and run-control events
- Android-style workspace file policy for scoped paths, archive entry guards, exact patch replacements, and diff summaries
- Android-style explicit tool handle registry for opaque scoped stateful tool references, TTLs, releases, and resource revocation
- Android-style iOS Agent action notification wrapper for private running/result operation updates, stable per-task notification IDs, action title derivation, and notification-safe executor filtering
- Android-style private data inventory for encrypted backup manifests, export eligibility, erase coverage, and identity rotation audits
- Android-style model data disclosure ledger and Settings dashboard for cloud model and paired Desktop requests, storing metadata-only event receipts, hashed conversation/task/turn IDs, destination blocking, and protected local persistence without retaining request content
- Android-style agent failure recovery payloads, recommended recovery actions, plan-only fallbacks, and retry instructions
- Android-style agent task liveness policy for progress watchdog warnings, timeouts, and terminal reply suppression
- Android-style continuous observation controller for post-action screen change and stability sampling
- Android-style observation context store for bounded, expiring, per-target observed context with conversation scoping, acknowledgement, and cleanup
- Android-style agent action recovery controller for timed-out low-risk navigation retries and manual handoff for unsafe failures
- Android-style agent action risk hardener for connector danger terms, custom device and Home Assistant control, and low-confidence visual OCR actions
- Android-style visual grounding for OCR layout roles, accessibility fusion, and screen element query matching
- Android-style phone execution authority for concurrent reads, serialized side effects, cancellation, and execution metadata
- Android-style final response identity keys and duplicate transcript coalescing
- Android-style fast local agent responses for bounded arithmetic, objectless new requests, and Android shared-storage path authorization
- Android-style attachment-aware conversation transport context with metadata-only references and private URI/data stripping
- Android-style agent conversation merge policy for agent-created child topics, provenance dedupe, and archived child handoff
- Android-style agent clarification policy for deciding when to execute, ask locally, or ask with model context
- Android-style agent Skill command parsing for save and upgrade requests
- Android-style final response self-check for empty, echo, acknowledgement-only, attachment, and identity mismatch repair signals
- Android-style Codex response policy for concise final prompts, rich-output input artifact filtering, and tool-noise sanitization
- Android-style agent task budget settings with Adaptive/Fast/Economy/Private/Custom profiles, per-task limits, and resource access policies
- Android-style global model call budget policy for rolling daily calls, leases, Token usage, reported cost, and concurrency caps
- Android-style provider profile catalog for cloud/local models and desktop Agent routing metadata
- Android-style connector route selection for reasoning-capable Agent/model targets and routed fallbacks
- Android-style agent resource catalog projection for callable targets, system tools, and native tools
- Android-style global realtime context projection for cognition, research, autonomous runs, long-horizon goals, and event-pipeline health with secret-safe model prompt rendering
- Android-style iOS global autonomous action authority and graph policy for host-owned proposal normalization, dependency resolution, cycle rejection, ready action ordering, and lease reservation
- Android-style iOS global proactive discovery policy for cross-topic conflicts, synthesis candidates, durable-goal stalls, material risks, high-value opportunities, daily task budgets, scan leases, changed-finding cooldowns, and backup-safe discovery state codec
- Android-style routing requirement analyzer for live data, private/offline, background, long-running, and Chinese task signals
- Android-style phone capability catalog with iOS 15+ permission, consent, availability, and native coverage boundaries
- Android-style phone native tool catalog descriptors for app-private workspace tools, phone action adapters, default tool IDs, and capability-gated availability
- Android-style iOS system native tool compatibility catalog and user-visible handoff executor for the full Android telephony, SMS, contacts, calendar, Wi-Fi, audio, download, biometric, VPN, and device-policy tool set, with iOS 15+ sandbox boundaries instead of false execution claims
- Android-style iOS hardware native tool catalog and provider-backed executor for app-visible battery, power, storage, network, and Bluetooth settings handoff status workflows
- Android-style iOS Home Assistant native tool catalog, prompt-to-native-tool routing, and default REST provider for configured connection checks, bounded entity reads, secret-safe entity listing, idempotent service calls, and controller-state verification
- Android-style iOS notification native tool catalog and provider-backed executor for bounded GalaxySSI-visible notification listing, sensitive-content redaction, idempotent reply dispatch, and stale-target retry honesty
- Android-style iOS visible capture native tool catalog and provider-backed executor for foreground-only camera/photo and microphone/audio artifact receipts, runtime permission gates, user-visible consent, and verifier-enforced URI evidence
- Android-style iOS WebMedia native tool catalog and provider-backed executor for `web.*`, `browser.*`, `http.request`, `file.download`, `galaxyssi.web.*`, and `galaxyssi.ocr.content.recognize` with bounded HTTPS, explicit browser handles, content URI guards, local extraction, and iOS 15+ sandbox receipts
- Android-style iOS web intelligence native tool catalog and provider-backed executor for public HTTPS search/fetch/crawl/research, encrypted cache/extract/watch operations, untrusted evidence receipts, and Android wire-compatible `galaxyssi.web-intelligence.v1` outputs
- Android-style cloud web grounding adapter for provider-safe Web Intelligence function schemas, inline tool-call parsing, registry-backed execution, bounded tool JSON, source fallback text, and shared untrusted evidence envelopes
- Android-style iOS global proactive delivery policy for foreground-ready signals, safe conversation routing, owned topic-workspace notices, delivery leases, adaptive message budgets, topic cooldowns, and bounded global digest batches
- Android-style iOS global intelligence acquisition policy for research plan units, continuous monitoring baselines, stale evidence lease recovery, source canonicalization, evidence confidence scoring, and quality-gated follow-up units
- Android-style iOS global research executor policy for evidence-worker dispatch, model-call budget leases, connector response consumption, synthesis retries, local evidence fallback, continuous-monitor rescheduling, and proactive research result publication
- Android-style iOS global autonomous native tool and Skill host for relevant tool catalog prompts, host-side invocation inspection, confirmation gating, Skill workflow projection, step receipts, and action evidence verification
- Android-style iOS media native tool catalog and provider-backed executor for selected media metadata, user-visible playback handoff, and offline FFmpeg typed-preset transcode with workspace path guards and disabled-network receipts
- Android-style iOS self-evolution native tool catalog and provider-backed executor for Android wire-compatible `galaxyssi.evolution.*` task status, task creation/listing, isolated candidate prepare/patch/rollback, self-evolution consent, and review-only patch receipts
- Android-style iOS Desktop remote native tool catalog and provider-backed executor for paired Desktop Windows status/process, task workspace file/archive, terminal, and Office document operations with GalaxySSI Link receipts and remote verification evidence
- Android-style iOS Desktop Control wire models for `desktop.*` action ids, multi-surface display/window catalogs, combined remote-control state snapshots, Android-compatible executor request construction, bounded screenshot streams, three-layer perception snapshots, durable task pause/takeover summaries, and identity-bound action receipt verification
- Android-style paired Desktop marketplace projection for `capability_manifest.tool_marketplace` items with iOS-side bounds, permission diffs, update/rollback state, and active desktop-session filtering
- Android-style iOS MCP native tool catalog and provider-backed executor for `galaxyssi.mcp.connections.list`, `galaxyssi.mcp.tools.list`, and `galaxyssi.mcp.tool.call` with MCP host policy/audit metadata
- Android-style iOS on-device runtime native tool catalog and provider-backed executor for `galaxyssi.runtime.*` status, workspace checkpoint, trusted pack listing/installation, and bounded sandbox execution receipts
- Android-style iOS runtime project workbench for durable per-conversation project files, private runtime-output filtering, quota-checked sync, stored ZIP artifact packaging, and checkpoint/rollback recovery without exposing host paths
- Android-style iOS desktop artifact handoff for encrypted fragmented artifact ingest, SHA-256 reassembly, app-private storage, safe rich-output card references, runtime artifact preview/save payloads, and text/ZIP actions without exposing host paths
- Android-style conversation Skill lifecycle runtime for learned workflow manifests, installed Skill state, raw manifest validation, typed parameter/resource template expansion, request matching, parameterized task reuse, compiler-generated native/orchestration steps, and Android wire-compatible recorded run fields
- Android-style Skill execution engine and version manager for ordered native tool invocation, failure fallback, use-count recording, learned Skill upgrades, and rollback to earlier installed versions
- Android-style Skill package installer/exporter for signed manifest ZIP inspection, safe entry validation, executable-content rejection, unsigned local approval, and disabled-by-default third-party installation
- Android-style Agent learning engine for preference capture, correction detection, repeated-failure memory, trusted runtime execution evidence, reviewed Skill proposals, and approved Skill upgrades
- Android-style model tool-loop context compactor for preserving assistant tool-call/result pairs, summarizing older tool activity, keeping unresolved calls, and shrinking oversized tool outputs under token pressure
- Android-style model tool protocol adapters for OpenAI-compatible, Anthropic, and Gemini providers, including native tool catalog encoding, conversation history encoding, tool-call decoding, usage metadata, bounded tool results, and malformed/unknown tool rejection
- Android-style model tool loop for iterative model-native tool execution, manifest hashing, budget enforcement, repeated-call detection, approval pause/resume, idempotent retries, cancellation propagation, and workspace binding before native tool invocation
- Android-style model plan parser for fenced/raw JSON action plans, allowed action kinds, dependency and output graph validation, local screen/app/native-tool resolution, task-complete replan markers, native-tool risk mapping, and bounded fallback-ready rejection
- Android-style model planning prompt builder for constrained JSON schema instructions, compact fast/economy prompts, screen/app/connector/native-tool inventories, replan and execution-history context, runtime-tool eligibility, and sensitive connector-output redaction
- Android-style guarded model agent planner core for settings/safety/private/fast/sensitive-route gating, safe low-risk native-tool exposure, prompt invocation, parser-enforced model output acceptance, risk hardening, and deterministic fallback profiles
- Android-style cloud model planning provider for structured planner prompts over existing OpenAI-compatible, Anthropic, and Gemini cloud contacts with credential preflight and model-planner invocation bridging
- Android-style cloud model native tool-loop planning provider for async OpenAI-compatible, Anthropic, and Gemini tool turns, safe executable registry subsetting, Android planner budgets, permission projection, and structured fallback when no safe native tools are available
- Android-style model planner contact resolution for preferred cloud model selection, stored-order fallback, selected-model normalization, readiness filtering, and guarded planner/provider construction
- Android-style agent plan factory for connector dedupe, empty-plan reasoning fallback, route resolution, and paired-contact permission projection
- Android-style native tool registry for descriptor lookup, JSON-schema input validation, permission and consent gates, deterministic catalog export, and idempotency-key replay protection
- Android-style AgentAction native tool adapter for legacy phone action calls, receipts, provenance, result metadata, and preflight rejection results
- Android-style native tool invocation pipeline for executable registration, progress hooks, output validation, verification, cooperative cancellation/timeouts, and successful idempotent result replay
- Android-style AgentAction native tool executor wrapper for running legacy phone action executors through native tool registry calls and catalog-built action executables
- Android-style global background execution budget for power-save, battery, network validation, and metered-research deferrals
- Android-style workspace native tool executor for app-private file and ZIP archive workflows through native tool registry calls, including stored and deflated ZIP extraction
- Android-style custom device connector configuration for HTTP REST, MQTT, WebSocket, TCP, UDP, MCP, GalaxySSI Agent, BLE, and Matter/Thread targets
- Android-style MCP tool security and audit policy for risk assessment, permission decisions, parameter redaction, Android-wire audit records, bounded in-memory and file-backed audit retention, stable codec persistence, and scoped clearing
- Android-style Home Assistant configuration with enabled state, local server URL, Keychain access token storage, and default entity target
- Android-style model planner settings for model-driven planning, replanning, coordination, privacy sharing, and task-control limits
- Android-style agent autonomy guard for tool-call budgets and repeated connector, device, URL, or app loop blocking
- Android-style active turn policy for interrupting, steering, or separating new user requests while an agent task is in progress
- Android-style global capability observations for local-only authorization, MCP, agent, Home Assistant, custom-device, and resource-health lifecycle events
- Android-style Global Memory durable context compiler with topic/project graph relevance, entity relation expansion, temporal world selection, untrusted evidence prompt sections, conflict notices, and bounded output
- Android-style Global Memory evolution safeguards for approval/rejection application, supersession chain integrity, inbox candidate isolation, private-candidate redaction, review/audit outcome records, and strengthened evidence merging
- Android-style Global Memory critic audit for expired memory retirement, duplicate consolidation, unresolved conflict and stale candidate findings, theme clustering, and audit scheduling
- Android-style Global Memory evolution persistence codec and store for inbox, audit report, evolution records, append dedupe, Android-keyed export, restore, and bounded retention
- Android-compatible encrypted `.hcbak` backup envelope with iOS local state, Link peers, voice settings, messages, and cloud API secrets restore
- QR scanning with AVFoundation
- Speech recognition and microphone capture settings with iOS permission prompts, Android-style wake words, wake threshold, welcome text, speak replies, Android-style TTS request guarding, voice routing preferences, Android-style PCM/VAD endpointing, and Android-style voice provider capability readiness for local Whisper, iOS Speech, offline ASR, cloud ASR, system TTS, and Edge TTS
- Android-style realtime voice health snapshots for wake word, ASR, and TTS components, including runtime activity, recent success/failure freshness, dependency blocking, and iOS speech capture health reporting
- Android-style iOS PCM voice capture foundation with sample-frame models, ring-buffered speech segments, adaptive VAD endpointing, WAV export, feature flag parity, and AVAudioEngine tap integration for iOS 15+
- Android-style iOS Local Whisper ASR foundation with shared model catalog, `asr_model` voice setting parity, PCM16 WAV decode/resample, language normalization, verified model-file preflight, loaded-model lifecycle marking, stateful runtime/session lifecycle abstraction, native whisper.cpp CPU/Accelerate runtime, runtime-backed decode scheduler adaptation, adaptive realtime partial policy, prioritized Whisper decode scheduling, live Whisper transcription sessions, live session eligibility planning, live capture partial-window control, coordinator transcript bridging, Whisper text stabilization, and content-free ASR latency trace events
- Android-style iOS voice transcript correction foundation with risk classification, protected entity consistency checks, second-pass trigger policy, idempotent execution ledger, second-pass request planning, cancellable second-pass coordination, corrected-transcript result handling, correction journal context blocks, and planner context injection
- Android-style iOS Whisper model download manager with mirror-backed request metadata, trusted-source retry, persistent progress/failure/success state, completed-file validation, availability gating, and deletion cleanup
- Android-style iOS Whisper model catalog with Android-matched tiny/base/small/medium/large/turbo and Q5 profile metadata for size, SHA-256, RAM, window, quantization, execution-mode, and experimental gates
- Android-style iOS Whisper model storage verification for expected size, SHA-256, install metadata, staging cleanup, atomic replacement, active-model delete protection, and native-load revalidation
- Android-style iOS Whisper download policy enforcement for offline/space gating, large-model metered-network confirmation, and locale-aware HuggingFace versus hf-mirror source ordering
- Android-style iOS Whisper legacy model migration that verifies old flat-file downloads and atomically moves them into the private model storage layout
- Android-style iOS Whisper model settings page with profile/lifecycle row details, current/use/download/retry/waiting row actions, removable installed model rows, locale-aware foreground downloads, and automatic ASR model selection after validation
- Android-style iOS voice provider settings for wake engine, local Whisper ASR provider, TTS provider, and Microsoft Edge voice wire values, including backup/restore persistence
- Android-style iOS ASR provider routing policy that prefers ready Local Whisper and explicitly falls back to iOS Speech capability when Whisper is blocked by runtime/model readiness
- Android-style iOS Microsoft Edge TTS foundation with Edge WebSocket protocol messages, MP3 audio synthesis, provider-aware reply playback routing, and latency/runtime health events
- Android-style voice interaction coordinator for hold-to-talk sessions, canonical capture/ASR/routing/agent/TTS phases, one-shot final transcript routing commands, cancellation handoff, observer reattachment, and restart-safe session isolation
- Android-style iOS speech-capture coordinator bridge for mapping native Speech start/partial/final/stop/error events into the shared voice interaction state machine without routing duplicate transcripts
- Android-style iOS voice transcript route policy for resolving final speech commands to native agent, cloud model, remote agent, or local conversation targets with auto-send gating
- Android-style iOS system TTS reply playback for voice-triggered incoming replies, including spoken-text bounds, TTS runtime health, playback-start coordinator events, and session completion after speech finishes
- Android-style voice latency tracing for content-free session events, monotonic duration metrics, once-only event dedupe, privacy-filtered attributes, terminal outcome rates, and percentile diagnostics
- Android-style iOS voice latency wiring from Speech capture and system TTS playback into shared trace sessions for ASR and spoken-reply timing diagnostics
- UserNotifications integration for incoming background messages

## Compatibility Note

Android uses libsignal-backed Signal sessions after the encrypted pairing claim is accepted. iOS now has the matching `LibSignalClient` CocoaPod integration, an encrypted persistent Signal store, bundle exchange, and `prekey`/`signal` MQTT wire adapter. Run CocoaPods from `apps/ios` before building so `canImport(LibSignalClient)` enables the native session path; without the Pod, the app keeps the explicitly labelled legacy preview transport for development compatibility.

## iOS Version

The deployment target is iOS 15.0. Newer platform affordances are avoided unless guarded by the app layer.

## Source Layout

Swift source is split by functional domain rather than by a fixed size rule. Keep new iOS parity work in the closest existing domain file, or add a new domain file when a feature grows independently; `GalaxySSIModels.swift` should stay limited to shared foundation types.

## Build And Test

On macOS with Xcode installed:

```sh
xcodebuild test \
  -project apps/ios/GalaxySSI.xcodeproj \
  -scheme GalaxySSI \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

On any development host:

```sh
npm run check:ios
```

The cross-platform check verifies that the iOS project exists, keeps the iOS 15 deployment target, and includes the parity-critical source and test files.
