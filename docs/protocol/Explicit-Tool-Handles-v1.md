# Explicit Tool Handles v1

## 1. Purpose

GalaxySSI uses explicit tool handles when a tool needs state across calls. A
tool creates an opaque identifier such as `browser_id`, `mcp_handle_id`, or
`desktop_session_id`, returns it as ordinary tool output, and requires the model
or client to provide it on later calls.

Handles replace hidden application-level session state. They do not replace
GalaxySSI Link encryption, device identity, user authorization, or a tool's own
permission policy.

Contract identifier:

```text
galaxyssi.tool-handle/1.0
```

## 2. Handle Properties

Every handle binds:

- a resource kind;
- an internal resource identifier that is never returned publicly;
- an owner identifier;
- an optional conversation or task context;
- a bounded capability set;
- creation, last-use, and expiry timestamps;
- optional idle expiry;
- bounded public metadata.

Handle identifiers are random and opaque. Clients must not derive meaning,
authorization, routing, or resource identity from their text.

## 3. Validation

Every use validates all of the following:

1. the handle exists and has not expired;
2. the requested resource kind matches;
3. the caller matches the owner;
4. the conversation context matches when the handle is context-bound;
5. the handle grants the requested capability;
6. the underlying resource and its independent authorization remain active.

Failure is explicit. Missing and expired handles are retryable by creating a new
handle. Owner, context, kind, and capability mismatches fail closed.

## 4. Lifecycle

Handles are process-lifetime state and are not restored after an application
restart. A reconnecting client obtains a new handle from the authoritative
resource.

Handles are revoked when:

- the caller closes or releases them;
- the underlying connection or authorization is deleted;
- the underlying target changes;
- Desktop Executor is disabled;
- the time-to-live or idle timeout expires;
- bounded registry capacity evicts the least recently used entry.

Revoking a GalaxySSI Link pairing or Desktop authorization remains authoritative
even if a handle has not yet reached its expiry time.

## 5. Current Handle Kinds

### Desktop session

An active Desktop control authorization publishes a
`desktop_session_id`. Android binds it into every Desktop control request and
Desktop binds it into the signed execution receipt. The handle grants only the
tools listed by that authorization.

### MCP connection

GalaxySSI opens an `mcp_handle_id` before invoking a managed MCP connection.
Desktop Agent loops and local APIs call the handle rather than carrying an
implicit connection session. Updating the MCP transport target, disabling the
connection, or deleting it revokes all of its handles.

An MCP server may still issue a transport-level session identifier for protocol
compatibility. That transport detail is not a GalaxySSI handle and is never used
as GalaxySSI authorization.

### Browser session

Android exposes:

- `browser.session.create`;
- `browser.session.navigate`;
- `browser.session.close`.

Creation returns `browser_id`. Navigate and close require the same caller and
conversation context. Browser state is isolated, bounded, cookie-free, and does
not execute JavaScript.

## 6. Observability

Public handle records include the contract, handle ID, kind, capabilities,
scope, timestamps, use count, and safe metadata. They never include the internal
resource identifier or resource object.

Desktop exposes loopback-only handle status and lifecycle APIs. Capability
manifests advertise supported handle kinds so clients can fail closed instead
of silently falling back to implicit global state.

## 7. Compatibility

Tools that are stateless remain stateless. Existing one-shot tools such as
`browser.render` may remain available while stateful workflows use explicit
handles. A client that does not advertise Explicit Tool Handles v1 is treated as
lacking stateful tool support; there is no silent downgrade for Desktop control
requests.
