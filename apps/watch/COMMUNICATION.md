# Android transport parity

Wear OS compiles the Android `Mqtt*.kt` sources in `shared-link`; broker endpoints,
TLS settings, authenticated resume, path selection, hedging, receipt credit,
durable fragment assembly and duplicate handling are not separate watch copies.
`WatchLinkTransport` binds those components to the watch's encrypted task outbox
and Android's transactional Signal inbox. MQTT PUBACK is not peer acceptance.
Only a verified peer receipt matching the current route and ciphertext hash
acknowledges a queued message. Reconnection does not regenerate a Signal message.

The same `AgentRemoteRecoveryClient`, `AgentResultRecoveryClient`, page codec and
encrypted page database provide read-only recovery. Client route, conversation,
turn, source message, agent and remote task identity are checked; execution
generations fence stale results. A remote-generated task ID is bound only after
an exact client identity match. Result receipts are queued after local storage.

Search schemas, retrieval engines, evidence boundaries, citations, quality rules
and the research audit are compiled from Android. The Wear adapter retains a
bounded conversation loop and concise presentation. API requests interrupted by
process death are not automatically replayed; remote task recovery never reruns
tools. Phone-only local model runtimes and desktop control UI are not bundled.

Validation:

- `:shared-link:testDebugUnitTest` runs the Android transport contract tests.
- `:app:testDebugUnitTest` includes Android's recovery client tests and Wear task
  identity/generation regressions.
- `WatchRemoteDiagnosticTest` is opt-in (`remote_diagnostic=true`) and sends one
  Hello to the already paired Codex agent without changing credentials.
- The normal diagnostic prints path states and outcome lengths, never keys.
