# Browser operation reconciliation

## Problem

Losing an RPC response does not mean a website rejected an action. A submission
can reach the server while the client stops observing it. Previously, the CLI
generated an internal request ID that the Android caller did not know, and the
daemon discarded operation tracking immediately after completion. The model
could observe the live page but could not reconcile the specific outstanding
operation.

## Contract

- Android derives an opaque request ID from the browser scope, turn and native
  invocation ID before executing the helper. A retry of that invocation uses
  the same ID; another invocation or scope gets a different ID.
- The ID travels through the existing ephemeral environment channel, not shell
  arguments. It is consumed before service creation and included in unobserved
  outcomes even when the helper produces no structured response.
- `galaxyssi.browser.observe` accepts `operation_status` with `request_id`.
  This queries metadata without acquiring the browser context's action queue,
  submitting another action, starting a missing service, or granting host control.
- Status is `running`, `completed`, `failed`, or `unknown`. A failed receipt
  distinguishes explicit pre-dispatch rejection from an uncertain side effect.
- A completed receipt only means the browser operation returned. The model must
  inspect the live page or authoritative external state to verify business
  success. Neither a timeout nor an unknown receipt proves non-execution.
- Known request IDs cannot be dispatched again, including with changed arguments.
  This is a same-service replay guard, not an exactly-once guarantee for arbitrary
  website effects or a substitute for application-level idempotency keys.

## Lifetime and confidentiality

The per-scope daemon retains only operation name, opaque identifiers, timestamps,
status and structured error code. It does not retain operation arguments, URLs,
form values, page text, screenshots, cookies, host capabilities or exception text.
Completed metadata expires after ten minutes, with at most 1,024 completed
receipts retained. In-flight records are not evicted by that history budget.
Service death, expiry or eviction returns `unknown`; the model must reconcile
external state rather than infer that a retry is safe. Receipts are not written
to disk. Original tool observations remain governed by the encrypted Agent
journal and its scope.

## Verification

The regression matrix includes a real Chromium browser and controlled HTTP
server: a form POST reaches the server, its response is withheld until the RPC
observer times out, status remains running, duplicate dispatch is rejected,
the server response is released, and a subsequent page observation verifies
exactly one server-side submission. The completed receipt is then queried from
an independent CLI process; another scope cannot see it.

Additional tests cover stable identities, secure environment limits, explicit
rejection versus uncertain failure, missing receipts, bounded metadata retention,
secret-free storage, packaged helper presence and Android outcome wiring.
These are framework and controlled-browser tests, not evidence that a real
provider autonomously completes authenticated websites on the phone.

The wider goal still requires real-model authenticated operation, dependency
repair, managed-member browser ownership and long-running recovery acceptance.

## Validated increment: Android 1.4.188 / 1273

- Browser suites: 74 passed, including the actual Chromium/HTTP reconciliation
  scenario and daemon-death regressions; no skipped browser checks.
- Runtime-tools CI entry point: 102 passed, four Windows symlink-policy skips.
- Targeted Android JVM checks: 60 passed across five suites.
- Full current-workspace Android JVM run: 6,521 tests across 813 suites,
  zero failures/errors, five environment skips (Windows symlink support and
  isolated Blob cross-runtime prerequisites).
- S20U (SM-G9880): 66 final framework checks and two separate-process goal
  contract checks passed after in-place installation. The initial new device
  fixture lacked its required mutation idempotency key; it was corrected and
  the complete 66-check device matrix was rerun successfully.

The full workspace build and JVM run also included separately developed,
unstaged MQTT changes. Those changes are not part of this increment. The scoped
browser/JVM tests and clean staged-source repository guard provide the isolated
checks; neither fixture tests nor APK installation prove the wider autonomous
goal complete.
