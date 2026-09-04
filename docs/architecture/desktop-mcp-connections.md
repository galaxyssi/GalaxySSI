# Desktop MCP Connections

GalaxySSI Desktop treats MCP servers as managed connections rather than custom
Agent commands. Each connection has a typed transport, protocol policy,
permission policy, discovered identity, capability snapshot, health state, and
tool inventory.

Stateful GalaxySSI callers first open an explicit, scoped `mcp_handle_id` and
then invoke the connection through that handle. The handle binds owner,
conversation context, capability, expiry, and revocation while keeping the
underlying connection identifier private. See
[Explicit Tool Handles v1](../protocol/Explicit-Tool-Handles-v1.md).

## Supported transports

### Local process

`local_stdio` launches a configured MCP server process and communicates with
newline-delimited JSON-RPC over standard input and output. A working directory,
timeout, protocol version, default tool, automatic-use triggers, and permission
policy are stored as connection configuration.

The legacy `Content-Length` framing remains available as an explicit
configuration value for compatibility tests. New connections use the MCP
standard newline framing.

### Streamable HTTP

`streamable_http` connects to one MCP endpoint using HTTP POST. The client:

- negotiates the MCP lifecycle and protocol version;
- supports JSON and Server-Sent Events responses;
- carries the negotiated protocol and optional session identifier;
- prevents HTTP redirects;
- bounds request, response, tool, and pagination sizes;
- closes a server-issued session when the operation ends.

HTTPS is required for non-loopback endpoints by default. Plain HTTP on a
trusted LAN must be enabled explicitly on that connection.

## Authentication boundary

Header values are not stored in the MCP connection document. A connection maps
an HTTP header name to an operating-system environment variable name, for
example:

```text
Authorization=GALAXYSSI_MCP_TOKEN
```

GalaxySSI resolves the value only when opening the transport. The value is not
returned by the API, rendered in the UI, or written to the MCP audit log.

## Lifecycle state

Every connection stores one of these states:

- `configured`
- `connecting`
- `ready`
- `error`
- `disabled`

A successful probe records the server name and version, negotiated protocol,
top-level capabilities, tool identifiers, latency, and validation time. A
failure stores a bounded and redacted diagnostic. Changing only the permission
policy preserves the latest probe state; changing the transport target resets
the state to `configured`.

## Security and audit

MCP tool calls continue through the common MCP security policy. The audit
record identifies the connection, transport, source fingerprint, tool, redacted
parameters, inferred permissions, risk, decision, task and conversation, result
hash, duration, and bounded error.

Connection state and tool audit are separate:

- connection state answers whether the server is usable;
- tool audit answers what was attempted and why it was allowed or denied.

This separation lets routing use health without weakening per-tool approval.
