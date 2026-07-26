# SignalASI Web Intelligence

SignalASI Web Intelligence is a clean-room, built-in evidence acquisition layer for Android and Desktop. It does not embed or copy Wigolo or Firecrawl source code and does not require an MCP server for core operation.

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

## Local intelligence

SignalASI performs local result processing before any final model synthesis:

1. canonical URL deduplication
2. weighted reciprocal-rank fusion
3. query-title and query-excerpt overlap scoring
4. cross-source consensus scoring
5. authority and freshness scoring
6. a small inspectable local ranking model
7. deterministic score explanations

The ranker model is stored in `core/models/web-ranker-v1.json`. Android ships the same model as an application asset.

A 192-dimensional feature-hash embedding model supports local semantic cache search without a cloud embedding API. This model is deliberately small, deterministic, inspectable, and replaceable by a signed neural reranker pack later.

## Evidence boundary

Fetched content is always untrusted evidence. It is never treated as an instruction source.

Research operations produce:

- normalized search results
- source receipts
- fetched documents
- stable citation identifiers
- a bounded evidence brief
- a synthesis contract for the selected SignalASI model or Agent

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

Android persists documents, vectors, search responses, and watches in an Android Keystore-protected encrypted database. Desktop uses a process-local SQLite store under the application state root.

Cache inspection, local extraction, cached similarity search, and watch management remain available offline. Operations that require new public evidence report honest source failures when the network is unavailable.

## Platform integration

Android registers the operations through `AgentWebIntelligenceNativeTools` and exposes them to the native planner. Public web research is low risk and executes without an unnecessary confirmation prompt.

Desktop registers the same operation IDs through `DesktopNativeToolRegistry`. The shared IDs allow task plans, Skills, proactive jobs, and test fixtures to remain platform-neutral while preserving platform-specific transport and encrypted-storage implementations.

