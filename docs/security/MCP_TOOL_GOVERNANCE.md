# MCP Tool Governance

GalaxySSI treats an MCP connection as an external capability boundary. A configured
server is not automatically trusted to read data, change state, or execute a
destructive operation.

## Permission modes

| Mode | Read-only tools | State-changing tools | High-risk tools |
| --- | --- | --- | --- |
| Read only | Allowed | Blocked | Blocked |
| Ask before changes | Allowed | Requires explicit user approval | Requires explicit approval for every call |
| Trusted | Allowed | Allowed | Requires explicit approval for every call |
| Disabled | Blocked | Blocked | Blocked |

High-risk operations include deletion, credential and permission changes, payments,
shell or terminal execution, deployment, release, lock state, reboot, and shutdown.
Tool annotations from the MCP server are considered, but local policy remains
authoritative. Missing annotations default to a state-changing risk level.

## Audit contract

Every attempted tool call records:

- connection and tool identity;
- transport and source fingerprint;
- caller, conversation, and task identity;
- locally derived risk and required permissions;
- permission mode and decision;
- redacted parameter preview and cryptographic input hash;
- outcome, duration, output hash, and bounded error classification.

Android stores this ledger in encrypted application storage. Desktop stores it in
the user state directory using atomic replacement. Both stores are bounded and
remove records when their connection is deleted.

Raw outputs, credentials, bearer tokens, cookies, one-time codes, private keys, and
URL query strings are never stored in the audit preview. Hashes preserve correlation
without retaining raw sensitive values.

## Execution boundary

Permission evaluation happens after the actual MCP tool and arguments are selected,
but before `tools/call` or a declarative/local equivalent executes. Model output
cannot grant its own permission. Explicit approval is carried by trusted host
invocation context, not by MCP parameters.
