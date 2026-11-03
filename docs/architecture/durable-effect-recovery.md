# Durable effect recovery queries

## Why response-time recovery is insufficient

A native tool can finish an external action and then lose the Android process
before committing its result. The durable effect claim prevents a second
dispatch, but an `effect_outcome_unknown` without the original observation
identity leaves the model unable to query the outstanding operation.

Durable execution does not make arbitrary external side effects exactly-once.
Temporal's [operation lifecycle and idempotency documentation](https://docs.temporal.io/nexus/operations)
separates durable operation identity/result delivery from handler idempotency.
Similarly, Playwright's [actionability checks](https://playwright.dev/docs/actionability)
help execute an interaction but do not establish the user's business outcome.
GalaxySSI therefore retains an observation method before dispatch, rather than
automatically retrying an uncertain mutation.

## Generic contract

An adapter may provide an `AgentNativeEffectRecoveryQuery` containing a registered
read-only tool ID, exact version and arguments. The registry validates its
contract and commits it atomically with the effect ownership claim. Only then
may the original executor run. The query arguments are an immutable JSON
snapshot, not a mutable reference to the action input.

On recovery, the registry returns the persisted `recovery_query` with the unknown
effect observation. It never regenerates a new operation ID, calls the original
executor, invokes the observer automatically, completes the pending effect, or
declares business success. The model chooses the observation and verifies the
actual goal. This is a provider-independent tool contract, not a website-specific
repair script or a keyword router.

An executor result explicitly marked `outcome_unknown` also carries the original
query in its committed error observation, both immediately and on later replay.

The browser adapter binds its existing `operation_status` query to the original
helper request ID. User-control handoffs keep their separate durable event
protocol; they do not pretend to use a browser RPC operation ID.

## Isolation and failure behavior

- Queries live in the original encrypted Run Kernel effect claim, bound to the
  route/session/conversation/goal/task/turn and effect identity.
- A conflicting input does not receive the old query. Another scope creates or
  observes only its own effect. Observing a result does not acquire ownership.
- A failed claim write prevents dispatch. A provider cannot register a mutation,
  mismatched version or invalid arguments as its recovery observation.
- Committed results replay directly without availability checks or query setup.
- Legacy claims without recovery metadata remain unknown; no identity is invented.
- Service loss or expired browser receipts still require external verification.
  This does not turn process-local browser receipts into persistent web state.
- Browser query metadata contains opaque operation IDs only, not form values,
  passwords, cookies, page content or authentication capabilities.

## Verification scope

Unit tests cover immutable snapshots, crash-window replay, original-ID retention,
scope/input conflicts, invalid contracts, storage failure, legacy claims and
committed-result replay. A scripted model follows unknown effect -> original
observation -> separate goal verification -> final answer without another write.
That scripted adapter is not evidence of real-provider reasoning.

The phone process-death harness starts an independent controlled HTTP server,
uses ADB reverse on one explicitly selected device, and installs no dependencies.
The production browser adapter receives an injected transport to that server.
After the server has accepted one mutation, the phone process is killed before
the adapter returns. A new phone process reloads the encrypted claim, returns its
original query, and reads the server's original result. The external server must
count exactly one mutation and one observation. The harness removes only its own
ADB reverse mapping; device fixtures use a unique database and preserve it on
failure.

Run after installing the debug and test APKs:

```powershell
npm run test:android:effect-recovery -- --serial YOUR_ADB_SERIAL
```

This verifies actual Android process loss and an external side effect, but not
phone Linux Chromium transport or a real model's autonomous website completion.
Real-provider login, dependency repair, managed-member browser ownership and
long-running goal acceptance remain required parts of the overall objective.
