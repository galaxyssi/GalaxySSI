# Opt-in collaboration HTTP admissions

Android #3381 adds a host-only admission budget. The iOS equivalent uses
`configureCollaborationTrial(conversationID:runID:policy:)` before creating
the exact managed collaboration run. The policy fixes the cloud resource,
provider model ID, frozen protocol SHA-256, deadline and maximum request
admissions. This API is not exposed as a model tool or app setting.

The encrypted ledger commits the debit and exact wire request digest in
one transaction before network I/O. All scoped cloud rounds, including
follow-up model calls for tools and repairs, debit the same run. Failed or
cancelled requests never refund a debit. Reopening the same policy is
idempotent; changing it or retrying an already admitted receipt is rejected.

An enrolled trial uses complete JSON over a fresh, direct HTTP/1.1
connection for each admitted round. The transport sends only one POST,
validates TLS using the platform trust stack, refuses redirects and
authentication follow-ups, and never retries after a disconnect. It
requires uncompressed responses with bounded framing. Cleartext is
accepted only for the exact local loopback fixture. Ordinary conversations
continue to use the existing URLSession streaming path.

Local and paired Desktop routes are not metered and are rejected for a
configured trial. The separate recruited goal-work lane is also blocked
until it can attribute its calls to the exact parent trial. This budget
does not count provider-internal work, tools, tokens, cost or entire-trial
elapsed time; it cannot establish an equal-compute comparison.

Run `URLSessionCloudModelStreamClientTests` for HTTP framing and loopback
request counting, and `AgentTeamExecutionTests` for durable admission and
settlement behavior.
