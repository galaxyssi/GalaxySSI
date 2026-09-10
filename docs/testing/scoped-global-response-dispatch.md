# Scoped global connector response dispatch

## Observed dependency

After removing dashboard counting from startup hydration, the SM-T575 live case
`live-final-1788975917258` still took 18,420 ms to show its recovered reply.
Hydration took 1,641 ms and inbox queueing only 1 ms. The first queued response
took 1,893 ms to restore and 9,935 ms to consume. Global initialization overlapped
this interval, so elapsed times alone do not prove all consumption time is global
work.

Source inspection found an unconditional chain in
`GlobalSuperAgentRuntime.consumeConnectorResponse`: every ordinary conversation
reply initialized and searched cognition, autonomous-run, and research executors
before reaching its own conversation. The research store shares a lock with
global dashboard initialization.

## Change

Android 1.1.41 (927) uses existing structural conversation namespaces to select
the owning global executor before accessing its lazy instance. This is envelope
routing, not natural-language intent matching. The same typed scopes now produce
outgoing conversation identifiers, keeping producer and consumer names aligned.
Wire identifiers have not changed.

- Ordinary or malformed scoped replies do not initialize global executors.
- Cognition replies only visit cognition; actions/reviews visit autonomous runs;
  research replies only visit research. A scoped miss does not scan other stores.
- Store-level matching still requires the persisted source correlation and now
  also verifies provided conversation and turn identifiers. Wrong revision or
  research-unit turns cannot be accepted just because the source matches.
- Truly old durable replies with an empty conversation identifier retain ordered
  source lookup. Empty legacy fields do not override a mismatched present field.
- Research's legacy source fallback cannot bypass a modern unit/synthesis owner.

This does not enable global cognition, change privacy permissions or resource
selection, or submit global/private targets to an external Provider. Desktop,
ASR/QNN, encryption, pairing, and transport timeouts are unchanged.

## Verification scope

`GlobalConnectorResponseScopeTest` exercises lazy callback isolation, exact
namespace selection, false/true propagation, invalid sources, malformed IDs,
legacy short-circuiting, owner/turn mismatch, and review/synthesis turns.

`GlobalResponseDispatchIsolationDeviceTest` holds global repository storage in a
test-owned thread while passing an ordinary reply to the actual runtime. The
runtime must return false without waiting for that lock. The test releases the
lock in `finally`; it does not publish a message or insert a transcript response.

The real Codex four-phase recovery harness is separate: its exact-body,
single-entry, Activity recreation, and subsequent cold-start assertions remain
unchanged. Only those live checks prove user-visible recovery for that case.

Full device-reboot coordination, all runtime paths, real global-task recovery,
side-effect deduplication, representative latency percentiles, and the broader
goal's remaining acceptance matrix are not proven by these scoped tests.

## SM-T575 results and retained failure

- Full build succeeded in 7m 15s. There were 3,417 unit tests in 495 suites,
  zero failures/errors and five existing skips.
- Repository, 73-library AArch64 16 KB, and QNN package audits passed.
- On 1.1.40, the actual-runtime lock test timed out after ten seconds. After
  confirmed in-place installation of 1.1.41 it passed in 0.074 seconds with the
  global store still locked. No message was published by this dependency test.
- The original first-install timestamp remained 2026-09-07 07:17:23. No App data,
  pairing, model, or user conversation was deleted.

Real case `live-final-1788977107581` completed exactly one Codex execution and
passed deliberate dropping of its final reply. Its original conversation is
`bc0d7adf-3ae7-47e5-87b1-5aedfb5e846c`. The next process-death inbox phase failed
the unchanged 60-second body deadline after five query timeouts. UI and cold
phases were not run. The reply was not resubmitted, injected, or moved to another
conversation. **This change has not yet passed full live recovery acceptance.**

Desktop tracing shows lookup/page construction in milliseconds and publish
function completion in 192-290 ms. Read-only SQLite inspection then found eight
recent priority-95 records from this test interval still `queued`, with zero
send attempts. All priority-95 records were on the same sealed route; an
additional snapshot showed 51 queued, three published awaiting application
receipt, and 68 failed after six attempts. These counts include older tests and
must not be represented as eight or 51 model executions for this case.

`_publish_phone_payload` can complete after durable enqueue. Its duration is not
broker acknowledgement or device receipt. Queue inspection must precede any
claim that the public network caused these waits. Current route scheduling
counts `published` rows waiting for application receipts against capacity until
their exponential retry time; equal-priority per-route selection favors older
records. This is a candidate starvation mechanism requiring a separate queue
regression and fix, not permission to clear the backlog or restart Desktop to
make the failure disappear.

Evidence: `build/scoped-global-response-{build,before,after,repo,16kb,qnn}.log`,
the unit-summary JSON, and `build/live-final-1788977107581/` (failed inbox log,
recovery diagnostics, scoped monotonic stage timings, and one-execution check).
The last passing real UI sample remains the pre-change 18,420 ms sample; no new
live first-visible performance claim is made here.
