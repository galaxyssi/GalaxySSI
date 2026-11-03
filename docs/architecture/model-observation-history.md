# Paged model observation history

New Android native cloud and local model loops expose `galaxyssi.tools.history`.
After context handoff, a model can recover original tool evidence instead of
guessing omitted details or repeating a previously completed operation.

## Reading evidence

- List observations with `limit` (default 10, maximum 20), optionally filtering
  by exact `tool_id` or `failures_only`. Each row contains the canonical record
  index, call/invocation IDs, status, error code and a bounded message preview.
- Continue with `next_cursor` and the same filters. A cursor binds the exact
  loop owner, query and observed prefix. New observations do not shift its
  snapshot; a changed prefix or different scope invalidates it.
- Read a listed `record`, optionally selecting a JSON Pointer `path`. Detail
  contains original arguments and the complete structured tool observation.
  `offset` and `length` (default 4096, maximum 8192 UTF-16 code units) support
  lossless chunking; use `next_offset` without splitting surrogate pairs.
- Detail includes `encoding`, `total_characters` and `sha256`. The digest uses
  the existing canonical JSON codec on the selected text, not raw file bytes.

All results are explicitly historical, untrusted evidence. They do not verify
current external state or goal completion. The reader never re-executes the
underlying tool. Reading history does not advance the fresh-observation counter
that guards a repeated operation with an unknown outcome.

## Isolation and recovery

The host binds the reader to session, conversation, turn, task, workspace,
caller, loop and collaboration source identity. The tool cannot select a
different conversation. Assistant notes, provider signatures and opaque model
continuation state are not exposed. History-reader results are excluded from
the index to avoid recursive growth.

The reader indexes the canonical transcript incrementally. Each invocation uses
a stable transcript snapshot, and concurrent reads share a synchronized index.
Encrypted journal restoration reconstructs the same records and cursor prefix.

A durable, scope-bound catalog marker adds the tool only to new runs. Existing
runs with an initial checkpoint, planner catalog or local continuation retain
their original tool contracts; upgrading the App does not silently add tools to
a saved run. Changed marker ownership or contracts produce a recovery error.

## Validation and limits

Unit coverage checks paging, changed evidence, scope/filter isolation, Unicode
chunks, opaque-state exclusion, legacy catalogs, parallel reads and uncertain
mutation fencing. Device instrumentation closes and reopens the encrypted
journal and retrieves exact evidence without repeating the original tool.
These injected-adapter tests are not real-model website/login acceptance, and
database reopening in instrumentation is not a device-reboot test.

This is model-facing pagination, not disk paging of the entire execution log.
The existing loop still restores its canonical transcript in memory. Paired
Desktop ActionPlan execution and semantic memory retrieval are not changed.
Tool-schema token accounting remains separate work.

## Design reference

- [Anthropic: effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)
