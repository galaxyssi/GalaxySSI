# SignalASI Tool Marketplace v1

SignalASI Tool Marketplace is the unified discovery and installation surface for:

- built-in native tools;
- trusted MCP connections;
- reusable automation templates and workflow Skills.

The marketplace is an orchestration layer. It does not bypass the existing native tool, MCP, Skill, or proactive task runtimes.

## Contract

Desktop exposes `signalasi.tool-marketplace/1.0` through:

- `GET /api/tool-marketplace`;
- `POST /api/tool-marketplace/{item_id}/install`;
- `DELETE /api/tool-marketplace/{item_id}`.

The paired Desktop capability manifest also includes a read-only `tool_marketplace` snapshot. Android stores snapshots only for currently trusted paired Desktops and displays them separately from on-phone capabilities.

Every item has a stable ID, kind, semantic version, publisher, trust status, dependencies, installation state, and optional installation reference.

Supported kinds:

- `native_tool`;
- `mcp`;
- `automation`.

Supported installation states:

- `built_in`;
- `available`;
- `installed`;
- `needs_setup`;
- `unavailable`.

## Installation Rules

Native tools are shipped with the owning application. The marketplace reports real runtime availability and required permissions, but it never pretends to install a built-in tool.

MCP catalog items delegate to the existing MCP registry. Secret values are never stored in catalog records. Desktop MCP entries reference environment variable names, while Android entries continue through the existing authentication or signed local package flow.

Automation templates delegate to the existing Skill runtime on Android and the durable proactive task runtime on Desktop. Installed tasks retain their normal retry, concurrency, network, delivery, and audit policies.

## Trust Boundary

The v1 catalog is application-owned and allowlisted. Arbitrary downloaded code cannot register itself as a trusted marketplace item.

- Local MCP packages still require the existing package inspection and integrity checks.
- Local Skill packages still require manifest validation and explicit installation.
- Marketplace installation cannot grant permissions or consent on behalf of the user.
- Paired capability snapshots are informational and do not grant Desktop Executor access.
- Unknown item IDs and unsupported item kinds fail closed.

Signed remote catalogs, update channels, version comparison, rollback, and revocation are intentionally reserved for the next marketplace protocol revision.
