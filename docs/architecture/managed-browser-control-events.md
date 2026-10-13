# Managed browser control events

## Event-driven control

Team RUN and STOP intent is encrypted before a unique WorkManager event is
enqueued. PAUSE keeps pending browser wakes without polling a model. A RUN event
replaces the original pending browser recovery worker, avoiding stale retry
backoff. It does not resume an active human-controlled handoff.

The control worker uses an encrypted, per-Run index with 64-row keyset pages.
Index rows are routing hints, not authorization: the original encrypted browser
generation and managed dispatch must still agree. Startup backfills legacy
records and retries indexed work whose scheduling or host cleanup was interrupted.
Acknowledged returned wakes are removed, not reintroduced by index backfill.

## Stop and cleanup

STOP cancels only the original local execution identity. Under the same handoff
lock used by the initial browser request, active control becomes a durable
`browser_owner_stopped` interruption. Old UI actions cannot operate that handoff.
Exact member cancellation is scheduled before attempting host cleanup, so an
unavailable browser host does not delay the cancellation receipt.

Host cleanup uses the original handoff and scoped capability. It never converts
STOP into returned control, login success or a model observation. Cleanup failures
retain the index for a durable retry, even after the cancellation is acknowledged.
An `ok` envelope without confirmed agent control is not a cleanup acknowledgement.
A later parent control write cannot resume an explicitly retired generation.
Generation checks prevent an old cleanup from removing a replacement request.

Browser recovery still waits for the original process-owned execution lease.
Replacing a WorkManager observer does not create a concurrent model loop or
replay a browser mutation. Results retain the original managed response owner.

## Verification boundary

Android device fixtures cover immediate RUN routing, PAUSE, active STOP,
unavailable hosts, enqueue failures, foreign hints, generation replacement,
acknowledgement backfill and multi-page indexing. A separate force-stop test
verifies encrypted original requests, owner generations and control persistence
across processes. These tests use public synthetic assignments and injected
host/model responses. They do not constitute real-provider autonomous login or
long-duration website troubleshooting acceptance.
