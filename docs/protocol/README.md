# GalaxySSI Link Protocol

This directory contains protocol specifications, schemas, and compatibility notes shared by all GalaxySSI clients.

Additional protocol contracts:

- [Explicit Tool Handles v1](Explicit-Tool-Handles-v1.md)
- [Desktop Native Tool Execution v1](Desktop-Native-Tool-Execution-v1.md)
- [Phone-Native Tool Session v1](Phone-Native-Tool-Session-v1.md)
- [Super Agent Rich Output](Super-Agent-Rich-Output.md)
- [Self-Evolution V2 API](Self-Evolution-V2-API.md)
- [Web Evidence Pack v1](Web-Evidence-Pack-v1.md)
- [Collaboration Research Workspace v1](Collaboration-Research-Workspace-v1.md)

## Connector Model Options

A connector's `invocation_profile` can advertise an optional `model_aliases`
object mapping an older model ID to a canonical ID in `models`. A picker shows
only the canonical entries and can resolve a stored alias before building the
invocation. The desktop also accepts its advertised legacy IDs from older
clients. Alias resolution does not rewrite a saved conversation or its reasoning
effort.

## Agent Conversation Identity

Agent messages use three independent identifiers:

- `conversation_id` identifies the durable user-visible Agent session.
- `turn_id` identifies one user request and its resulting assistant response.
- `task_id` identifies one execution task inside a turn.

The Android client includes `conversation_id` and `turn_id` inside the encrypted
GalaxySSI Link payload. Desktop connectors bind task lifecycle events to the
originating turn. Codex App Server integrations reuse one Codex thread for each
GalaxySSI conversation while other connectors receive a bounded conversation
summary and recent dialogue.

Task lifecycle events may include bounded `output_files` metadata using paths
relative to the isolated task workspace. Provider-reported `input_tokens`,
`output_tokens`, and `cost_micros` are retained when available.

Deleting a conversation sends `type: agent_conversation_delete` with its
`conversation_id` and known `task_ids`. The paired Desktop removes matching task
records, Codex thread mappings, and temporary/log directories while preserving
saved output files to prevent accidental data loss.
