# SignalASI iOS

SignalASI iOS is a native SwiftUI client for iOS 15 and later. It mirrors the Android client's primary mobile surface: chats, contacts, SignalASI Link pairing, direct cloud model contacts, voice capture settings, local notifications, and durable local state.

## Current Scope

- SwiftUI app target and XCTest target in `SignalASI.xcodeproj`
- Chats and contacts backed by a local Codable store, including searchable chat/contact lists, unread conversation summaries, local message deletion, chat history clearing, message details, and delivery trace inspection
- Android-compatible SignalASI Link v1 QR validation, route generation, pairing claim encryption, envelope creation, and envelope validation
- Native MQTT 3.1.1 transport over TLS for pairing topics, Link topics, and background message delivery handoff
- Durable Link outbox, exponential retry, delivery acknowledgements, Android-style delivery trace stages, inbound dedupe, and Android-compatible `signal-chunk` MQTT payload chunking
- Android-style MQTT publish result acceptance, reconnect backoff, and relationship subscription recovery policies
- Android-compatible unified command payloads for desktop MQTT commands and structured command results
- Android-compatible `signalasi_contact` QR export/import with pending friend requests, approve/reject handling, and verified contact creation
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
- Android-style Agent confirmation policy for Direct, Confirm Once, and Confirm Always action gating
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
- Android-style private data inventory for encrypted backup manifests, export eligibility, erase coverage, and identity rotation audits
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
- Android-style routing requirement analyzer for live data, private/offline, background, long-running, and Chinese task signals
- Android-style phone capability catalog with iOS 15+ permission, consent, availability, and native coverage boundaries
- Android-style phone native tool catalog descriptors for app-private workspace tools, phone action adapters, default tool IDs, and capability-gated availability
- Android-style iOS system native tool compatibility catalog and user-visible handoff executor for the full Android telephony, SMS, contacts, calendar, Wi-Fi, audio, download, biometric, VPN, and device-policy tool set, with iOS 15+ sandbox boundaries instead of false execution claims
- Android-style iOS hardware native tool catalog and provider-backed executor for app-visible battery, power, storage, network, and Bluetooth settings handoff status workflows
- Android-style iOS Home Assistant native tool catalog and provider-backed executor for connection status, bounded entity reads, secret-safe entity listing, idempotent service calls, and controller-state verification
- Android-style iOS notification native tool catalog and provider-backed executor for bounded SignalASI-visible notification listing, sensitive-content redaction, idempotent reply dispatch, and stale-target retry honesty
- Android-style iOS visible capture native tool catalog and provider-backed executor for foreground-only camera/photo and microphone/audio artifact receipts, runtime permission gates, user-visible consent, and verifier-enforced URI evidence
- Android-style iOS WebMedia native tool catalog and provider-backed executor for `web.*`, `browser.*`, `http.request`, `file.download`, `signalasi.web.*`, and `signalasi.ocr.content.recognize` with bounded HTTPS, explicit browser handles, content URI guards, local extraction, and iOS 15+ sandbox receipts
- Android-style iOS web intelligence native tool catalog and provider-backed executor for public HTTPS search/fetch/crawl/research, encrypted cache/extract/watch operations, untrusted evidence receipts, and Android wire-compatible `signalasi.web-intelligence.v1` outputs
- Android-style iOS media native tool catalog and provider-backed executor for selected media metadata, user-visible playback handoff, and offline FFmpeg typed-preset transcode with workspace path guards and disabled-network receipts
- Android-style iOS self-evolution native tool catalog and provider-backed executor for Android wire-compatible `signalasi.evolution.*` task status, task creation/listing, isolated candidate prepare/patch/rollback, self-evolution consent, and review-only patch receipts
- Android-style iOS Desktop remote native tool catalog and provider-backed executor for paired Desktop Windows status/process, task workspace file/archive, terminal, and Office document operations with SignalASI Link receipts and remote verification evidence
- Android-style iOS Desktop Control wire models for `desktop.*` action ids, multi-surface display/window catalogs, combined remote-control state snapshots, Android-compatible executor request construction, bounded screenshot streams, three-layer perception snapshots, durable task pause/takeover summaries, and identity-bound action receipt verification
- Android-style paired Desktop marketplace projection for `capability_manifest.tool_marketplace` items with iOS-side bounds, permission diffs, update/rollback state, and active desktop-session filtering
- Android-style iOS MCP native tool catalog and provider-backed executor for `signalasi.mcp.connections.list`, `signalasi.mcp.tools.list`, and `signalasi.mcp.tool.call` with MCP host policy/audit metadata
- Android-style iOS on-device runtime native tool catalog and provider-backed executor for `signalasi.runtime.*` status, workspace checkpoint, trusted pack listing/installation, and bounded sandbox execution receipts
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
- Android-style agent plan factory for connector dedupe, empty-plan reasoning fallback, route resolution, and paired-contact permission projection
- Android-style native tool registry for descriptor lookup, JSON-schema input validation, permission and consent gates, deterministic catalog export, and idempotency-key replay protection
- Android-style AgentAction native tool adapter for legacy phone action calls, receipts, provenance, result metadata, and preflight rejection results
- Android-style native tool invocation pipeline for executable registration, progress hooks, output validation, verification, cooperative cancellation/timeouts, and successful idempotent result replay
- Android-style AgentAction native tool executor wrapper for running legacy phone action executors through native tool registry calls and catalog-built action executables
- Android-style global background execution budget for power-save, battery, network validation, and metered-research deferrals
- Android-style workspace native tool executor for app-private file and ZIP archive workflows through native tool registry calls, including stored and deflated ZIP extraction
- Android-style custom device connector configuration for HTTP REST, MQTT, WebSocket, TCP, UDP, MCP, SignalASI Agent, BLE, and Matter/Thread targets
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
- Speech recognition and microphone capture settings with iOS permission prompts, Android-style wake words, wake threshold, welcome text, speak replies, voice routing preferences, and Android-style voice provider capability readiness for local Whisper, iOS Speech, offline ASR, cloud ASR, system TTS, and Edge TTS
- Android-style realtime voice health snapshots for wake word, ASR, and TTS components, including runtime activity, recent success/failure freshness, dependency blocking, and iOS speech capture health reporting
- UserNotifications integration for incoming background messages

## Compatibility Note

Android uses libsignal-backed Signal sessions after the encrypted pairing claim is accepted. This iOS foundation keeps the same protocol boundaries and pairing claim format, but the full libsignal Swift bridge still needs to be wired before paired desktop chat can be considered end-to-end encrypted parity.

## iOS Version

The deployment target is iOS 15.0. Newer platform affordances are avoided unless guarded by the app layer.

## Source Layout

Swift source is split by functional domain rather than by a fixed size rule. Keep new iOS parity work in the closest existing domain file, or add a new domain file when a feature grows independently; `SignalASIModels.swift` should stay limited to shared foundation types.

## Build And Test

On macOS with Xcode installed:

```sh
xcodebuild test \
  -project apps/ios/SignalASI.xcodeproj \
  -scheme SignalASI \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

On any development host:

```sh
npm run check:ios
```

The cross-platform check verifies that the iOS project exists, keeps the iOS 15 deployment target, and includes the parity-critical source and test files.
