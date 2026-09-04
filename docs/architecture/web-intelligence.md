# GalaxySSI Web Intelligence

GalaxySSI Web Intelligence is a clean-room, built-in evidence acquisition layer for Android and Desktop. It does not embed or copy Wigolo or Firecrawl source code and does not require an MCP server for core operation.

## Product contract

The implementation exposes ten first-class operations on both platforms:

- `search`
- `fetch`
- `crawl`
- `extract`
- `cache`
- `find_similar`
- `research`
- `agent`
- `diff`
- `watch`

The wire contract is defined in `core/protocol/web-intelligence-v1.schema.json`.

## Source coverage

The initial catalog contains 32 source adapters across:

- general search
- news
- code and package registries
- official documentation
- academic publications
- technical communities
- encyclopedic knowledge

Searches use bounded parallel fan-out. Each source receives an independent receipt and failure state. A slow, blocked, malformed, or unavailable source cannot erase successful results from other sources.

## Adaptive source network

Source selection is adaptive rather than a fixed fan-out list. Android and Desktop persist a health ledger for each source containing:

- successful, empty, and failed attempts
- consecutive failures
- exponentially weighted latency and result yield
- last attempt and last success time
- circuit state and recovery time

Three consecutive failures open a source circuit. Cooldown grows from one minute to at most thirty minutes when recovery probes keep failing. An expired circuit enters a half-open recovery probe on the next relevant request. Cancellation never reduces source reputation.

Automatic routing combines query vertical, language, authority, historical reliability, latency, evidence yield, and a bounded exploration bonus. Explicitly selected sources bypass the circuit so a user or diagnostic task can force a recovery probe. Every response identifies the strategy, selected source health, and skipped circuits.

Search profiles provide predictable resource budgets:

- `fast`: up to 6 sources and a 6 second shared deadline
- `balanced`: up to 18 sources and a 15 second shared deadline
- `deep`: up to 32 sources and a 35 second shared deadline

Callers may still override fan-out and deadline explicitly. The `cache` operation exposes `source_health` inspection and `reset_source_health` maintenance without adding a separate external tool.

## Local intelligence

GalaxySSI performs local result processing before any final model synthesis:

1. canonical URL deduplication
2. weighted reciprocal-rank fusion
3. query-title and query-excerpt overlap scoring
4. cross-source consensus scoring
5. authority and freshness scoring
6. a small inspectable local ranking model
7. deterministic score explanations

The ranker model is stored in `core/models/web-ranker-v1.json`. Android ships the same model as an application asset.

A 192-dimensional feature-hash embedding model supports local semantic cache search without a cloud embedding API. This model is deliberately small, deterministic, inspectable, and replaceable by a signed neural reranker pack later. It ranks and retrieves evidence; it is not presented as a general answer-generation model.

## Evidence boundary

Fetched content is always untrusted evidence. It is never treated as an instruction source.

Research operations produce:

- normalized search results
- source receipts
- fetched documents
- stable citation identifiers
- a bounded evidence brief
- a synthesis contract for the selected GalaxySSI model or Agent

The selected model or Agent creates the final natural-language answer. The retrieval layer does not claim that deterministic extraction is model reasoning.

## Security

Public network access uses:

- HTTPS only
- public-address DNS validation
- DNS pinning
- redirect-by-redirect revalidation
- response size limits
- time budgets
- cancellation
- no browser cookies
- no implicit local-network access

Android persists documents, vectors, search responses, watches, and source health in an Android Keystore-protected encrypted database. Desktop uses a process-local SQLite store under the application state root.

Cache inspection, local extraction, cached similarity search, and watch management remain available offline. Operations that require new public evidence report honest source failures when the network is unavailable.

## Platform integration

Android registers the operations through `AgentWebIntelligenceNativeTools` and exposes them to the native planner. Public web research is low risk and executes without an unnecessary confirmation prompt.

Desktop registers the same operation IDs through `DesktopNativeToolRegistry`. The shared IDs allow task plans, Skills, proactive jobs, and test fixtures to remain platform-neutral while preserving platform-specific transport and encrypted-storage implementations.

Direct cloud-provider conversations on Android and Desktop use the same Web
Intelligence services through provider-safe function aliases. Time-sensitive
interpretation uses the device-local date, time, and UTC offset. Every request
receives the same tool catalog, and the model decides from the user's meaning
whether evidence is needed. Structured function calls and provider-specific inline DSML calls
are normalized into the same bounded execution loop; internal tool markup is
never rendered as an assistant answer.
