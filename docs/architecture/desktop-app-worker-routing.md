# Authorized App To Worker Routing

Desktop 1.1.35 connects eligible ordinary App requests to the existing durable
worker queue, without a special prompt, Android packet change or UI redesign.
Routing is off by default. Pairing alone never authorizes offload or starts a
worker controller. This is a bounded feature delivery, not multi-host acceptance.

## Explicit Setup

All APIs below require a loopback caller and the existing `x-galaxyssi-token`
credential of the Desktop receiving the request. Never place that token in MQTT.

1. On the coordinator, explicitly enroll an existing paired worker with
   `PUT /api/agent/workers/{worker_route}`. Supply an operator-chosen `worker_id`,
   `max_parallel`, and `providers: ["codex"]` under the existing enrollment API.
2. On that worker, explicitly activate
   `PUT /api/agent/worker-client/{coordinator_route}` under the existing controller
   API. Its bounded parallelism is at most ten and shares the model work pool;
   workspace and sandbox restrictions still apply.
3. On the coordinator, authorize one paired App using
   `PUT /api/agent/worker-routes/{app_route}` with
   `{"worker_routes": ["paired-worker-route"]}`. The App must have full Desktop
   Executor access. Each target must already be enrolled for Codex.

`GET /api/agent/worker-routes/{app_route}` returns configured state, not worker
readiness. Inspect the existing workers API for current enrollment/session state.
`DELETE` disables future admission only: it neither cancels nor reauthorizes old
tasks. At most 10,000 App policies and 128 distinct targets per policy are stored.
Policy mutation is not exposed through MQTT. No new enrollment UI is included.

## Admission And Fallback

The existing MQTT request validation and permission checks run first. Eligible
requests are standalone/sequential Codex tasks with no active conversation task.
Active-turn steering, recovered local tasks, programmatic video, explicit image
artifact production and structured connector responses retain the existing path.
Other providers also remain local.

The original prompt, selected model/reasoning, execution budget and request
snapshot are retained. Native PNG/JPEG/WebP/GIF inputs are supported. Transferred
files are resolved by the exact original App/conversation/task/turn scope and
checked against their SHA-256 before embedding. Images are not recompressed.
Each image is limited to 256 KiB raw, the prompt to 256 KiB UTF-8, and portable
job JSON to 500 KiB, reserving room under the 512 KiB worker poll envelope limit.
Unsupported or oversized input falls back before queue admission. This does not
change the ordinary attachment transport limits.

Policies permitting the requested cloud, paid, network and artifact capabilities
are checked before offload. Missing, disabled or no-longer-authorized routes use
the already-authorized local path before admission. After successful admission,
the coordinator does not start a duplicate local provider. Storage failures are
not silently converted into local execution. Existing duplicate request fencing
still applies.

## Isolation And Persistence

Queue admission, the original recipient binding and queued notification commit in
one SQLite transaction. The full App/conversation/turn/task/execution-generation
identity and source message ID survive worker claim, report and notification.
The coordinator task manager observes worker-owned tasks without taking them
over. Waiting tasks use the existing bounded durable queue, not one thread each.

The policy binds both the App and every target to their current pairing identity
and access grant. Reusing a route or worker ID after re-pairing does not inherit
authorization. Reconfiguration affects new requests; old tasks keep their
admission-time bindings. Intentional reauthorization needs fresh trusted admission
with a new task ID. Before sending task payloads, including outbox retries, the
coordinator checks the current App binding against the original recipient.
Revoked or replaced identities cannot receive those old task results.

Existing Signal and outer MQTT encryption are unchanged. Private origin and
worker binding values are not serialized into public task status. The existing
`execution_view` reports the claimed worker ID after dispatch, survives task
projection reload, and requires no layout change. Before claim, no worker has
been selected yet.

## Verification And Limits

Final 2026-09-09 verification: the selected task/MQTT/worker/process regression
suite passed 600 tests and 314 subtests in 224.73s (four opt-in live cases skipped).
The App routing file was separately run with live Codex enabled: 16 tests and six
subtests passed in 22.68s. Desktop checks passed 29 tests, repository checks and
the staged whitespace check also passed.

`test_agent_worker_app_routing.py` covers default-off behavior, explicit API
authorization, two Apps using the same conversation name, original result scope,
re-pairing, revocation, restart observation, transaction rollback, input bounds,
verified native images, local fallback and no duplicate local dispatch.

The opt-in Windows test (`GALAXYSSI_LIVE_WORKER_CODEX=1`) enters through the actual
ordinary MQTT task handler, routes text and a native image from two synthetic
Apps, runs real Codex subprocesses through the worker controller, and checks both
returned identities and model answers. Its transport and coordinator are local
fixtures: it does not prove phone, public broker or separate-machine delivery.

Remaining acceptance includes deployment, real phone/broker/two-node operation,
network failures, remote cancellation, broader restart reconciliation, returned
artifact transport and concurrent multi-host load. A 10,000-entry queue does not
prove 10,000 simultaneous model calls. No APK installation or running Desktop
replacement is part of this PR. Per the revised delivery scope, work stops after
this feature's tests and PR; these broader items are not claimed complete.
