# GalaxySSI Tool Marketplace v1.1

GalaxySSI Tool Marketplace is the unified discovery and installation surface for:

- built-in native tools;
- trusted MCP connections;
- reusable automation templates and workflow Skills.

The marketplace is an orchestration layer. It does not bypass the existing native tool, MCP, Skill, or proactive task runtimes.

## Contract

Desktop exposes `galaxyssi.tool-marketplace/1.1` through:

- `GET /api/tool-marketplace`;
- `POST /api/tool-marketplace/{item_id}/install`;
- `POST /api/tool-marketplace/{item_id}/revoke`;
- `POST /api/tool-marketplace/{item_id}/rollback`;
- `DELETE /api/tool-marketplace/{item_id}`.

The paired Desktop capability manifest also includes a read-only `tool_marketplace` snapshot. Android stores snapshots only for currently trusted paired Desktops and displays them separately from on-phone capabilities.

Every item has a stable ID, kind, semantic version, publisher, trust status, dependencies, installation state, capability declaration, permission declaration, manifest digest, and optional installation reference.

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

## Release Lifecycle

Every managed release declares capabilities and permissions independently. The marketplace compares the active receipt with the available manifest before installation:

- added permissions require explicit approval;
- removed permissions are shown before upgrade;
- unchanged permissions remain visible for auditing;
- a manifest digest binds the displayed declaration to the release;
- environment variable references may be retained, but secret values never enter lifecycle receipts.

Desktop persists a bounded history of secret-free installation snapshots. Upgrade and uninstall preserve the previous verified state. Revoke disables execution while retaining configuration. Rollback atomically restores the previous MCP configuration or proactive automation and only advances the lifecycle receipt after restoration succeeds.

Android displays the same lifecycle fields for paired Desktops. On-phone native tools expose their real capability and Android permission declarations. On-phone Skills retain multiple validated versions and can roll back by disabling the current release and enabling the previous installed release.

## Trust Boundary

The v1 catalog is application-owned and allowlisted. Arbitrary downloaded code cannot register itself as a trusted marketplace item.

- Local MCP packages still require the existing package inspection and integrity checks.
- Local Skill packages still require manifest validation and explicit installation.
- Marketplace installation cannot grant permissions or consent on behalf of the user. New permissions must be acknowledged by stable permission ID.
- Paired capability snapshots are informational and do not grant Desktop Executor access.
- Unknown item IDs and unsupported item kinds fail closed.
- Rollback snapshots contain configuration and environment references only, never token, password, OTP, or API-key values.
- Built-in native tools cannot be uninstalled or rolled back independently from their signed host release.

Signed remote catalogs and release channels remain outside this contract. They must reuse this permission-diff and rollback boundary when introduced.
