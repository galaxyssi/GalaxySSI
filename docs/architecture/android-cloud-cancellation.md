# Android cloud request cancellation

Android 1.0.11 completes another part of the Run Kernel lifecycle work. The default physical
test device is SM-G9880 (S20 Ultra). This phase does not change Desktop, MQTT, model selection,
ASR/QNN, or the accepted roughly 20-second chat target.

## Ownership

- A cloud dispatch is identified by source message, initial contact, conversation, turn, task,
  and action. An exact match is required to cancel it. Cancelling one dispatch cannot cancel
  another conversation or a later turn.
- A dispatch lease has one terminal decision: completed or cancelled. Cancellation closes the
  active coroutine job, wakes retry backoff, and prevents subsequent candidates or final replies
  from being published by that cancelled dispatch. If completion already won, existing late
  response acceptance rules still govern delivery to the task.
- The native task cancel path, confirmed timeout path, task supervisor cancellation token, and
  managed control-plane cancellation all reach the same dispatch owner.
- A conversation request owns preparation, HTTP rounds and coroutine tool work as one child
  scope. Cancellation captures that scope, not a mutable lookup of the latest round. A reused
  request ID cannot replace an active owner.

## HTTP shutdown

The OkHttp stream bridge closes the call when its collector is cancelled, including while
waiting for headers or blocked reading the body. The request retains ownership until its reader
exits; an old reader cannot remove a replacement request. Setup and parsing stay on Dispatchers.IO.
Normal text ordering, provider adapters, usage, completion events, and partial error reporting
are unchanged.

The synchronous compatibility client receives a scoped cancellation token through its nested
HTTP rounds. The token is removed from its worker thread in finally and does not affect other
calls. Existing native tool callers retain their explicitly supplied tokens.

Closing a client connection is not proof that a commercial provider stopped all server-side
computation or billing. Already-running external tools without cooperative cancellation can
still finish their own bounded work; they must not start another model round after cancellation.
This change does not automatically replay uncertain side effects after process death.

## Durable outcome

The encrypted provider-attempt journal records `cancelled` separately from retryable provider
failure and closes its observation-only child Run with RUN_CANCELLED. Cancelling during backoff
preserves the preceding actual provider error. Cancelling after the provider completed but
before publication can leave a completed attempt inside a cancelled dispatch, accurately
distinguishing transport completion from task delivery.

No prompts, answers, API keys or raw provider errors are added to this journal. A cancelled
dispatch does not add a fake incoming failure message or advance to another provider.

## Validation

Focused JVM tests exercise cancellation before registration, stalled headers and bodies,
COMPLETE_JSON, duplicate IDs, early collector exit, compatibility HTTP, terminal races,
retry wakeup, exact routing isolation, and managed control-plane cancellation. Existing provider
normalization, stream ordering, merger, sentence, failure policy and fallback tests are retained.

Device tests use real loopback HTTP connections and temporary encrypted test databases, plus
the real MobileNativeAgent cancel entry point with injected execution dependencies. They do not
modify production contacts, credentials, pairing or messages, and do not charge a provider API.
Only the temporary test databases are deleted. Reinstall the main App with `adb install -r`,
never uninstall it or clear its data to run this suite.

The two-second cancellation test bounds detect a blocked local socket. They are test assertions,
not new user-task execution limits.

### Verified on 2026-09-06

- 103 focused JVM tests passed; Android production and instrumentation APK builds passed.
- S20U instrumentation: 20 passed, zero failures, four older opt-in process phases skipped.
  The new cases use real HTTP sockets on the device with fault-injected loopback responses.
- Cancellation: blocked body 8 ms, compatibility HTTP 5 ms, complete dispatch 6 ms. These are
  individual local measurements, not remote-provider latency percentiles.
- A live Chinese Codex question reached COMPLETED. User/final transcript timestamps differed
  by 23.638 seconds; the UI displayed 22 seconds of processing. This is one smoke sample.
- Cold reopen succeeded (Activity TotalTime 1,383 ms); the completed answer remained visible.
  The crash buffer was empty. First-install time remained 2026-09-05 23:09:22.
- Installed Android version: 1.0.11 (857). APK SHA-256:
  `4f8705e188f72617803c4ace870f8a409b7fd3b2534978d563c47bf9e8398aef`.
- Repository checks passed. The first device harness run rejected two non-void JUnit methods;
  their signatures were fixed and the complete device suite reran successfully. An earlier
  test-only compile error using AutoCloseable on the database was also fixed before that run.
