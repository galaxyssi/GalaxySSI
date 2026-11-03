# Discovering Validated Tools in Future Tasks

An executable tool release used to match only its review metadata and title.
Searching for the purpose or name of its exact source could therefore miss a
validated tool, even though the source was visible in the same group.

Capability recall now follows the release's host-owned source reference. It
adds `tool_name`, `tool_purpose`, `tool_environment`, `tool_dependencies`,
`tool_applies_when`, `tool_avoid_when`, and `tool_side_effects` as search fields.
`linked_sources` records the exact source revision and field names. The existing
page-local source cache avoids rereading shared definitions and is not reused
between queries or readers.

The source must be visible to this reader, have the exact identity and kind,
and have the source digest registered by the independently validated release.
Review conditions remain separate from source conditions. Neither replaces the
other, and snippets are not a complete read or permission to execute.

This does not index source code, test answers, generic ZIP artifacts or
unreleased source candidates as approved capabilities. It does not change
publication, release review, execution gates, group isolation or runtime checks.
Runtime admission still validates the exact tool, test plan and release lineage.
Ranking remains lexical within each page, not semantic or globally ranked.

## Verification

- `CollaborationToolCapabilityRecallTest`: future-task discovery and binding,
  source visibility, identity/digest mismatch, source/answer exclusion, and
  page-local read caching.
- `CollaborationExecutableToolDeviceTest`: encrypted storage reopen, cloud
  capability recall and exact future-task native invocation binding, using
  explicitly synthetic process receipts.
- `CollaborationSavedToolNativeDeviceTest`: broken/fixed Python tests in an
  already installed phone runtime, independent fixture release, fresh-task
  discovery by original purpose, then actual execution on a new input. No
  network, model calls, downloads or production task reruns.

These tests establish a discoverability and execution mechanism. They do not
establish autonomous learning, novel methods, matched-budget team superiority,
cross-domain transfer or long-term retention. The native test code and review
are developer-authored fixtures, not model-generated scientific evidence.
