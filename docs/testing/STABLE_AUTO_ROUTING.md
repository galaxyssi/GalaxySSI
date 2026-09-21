# Stable Auto Routing

## Contract

- The Auto subtitle and initial planning share an exact target ID per conversation.
- A healthy primary is used without ranking alternatives or applying a shadow-route promotion.
- Task compatibility, privacy, budget, connectivity, circuit state and capacity remain hard gates.
- An unavailable primary triggers normal task/latency/failure/capacity scoring. A dispatch or
  asynchronous provider failure also triggers fresh scoring; a stale fallback order is not authoritative.
- Manual locks, team assignments, durable effect claims and bounded fallback/retry trails remain in force.
- Results with unknown side effects must not start a new provider execution blindly.
- Actual dispatch updates the Auto identity. An older turn cannot overwrite a newer turn's identity.
- Conversation deletion clears its routing preference. Background cognition has no conversation header
  and retains its independent routing policy.

## Focused Regression

Run `AgentStableAutoRoutePolicyTest`, `AgentConnectorRouteSelectorTest`,
`AgentConnectorFallbackTrailTest`, `AgentConnectorFallbackActionTest`, and
`AgentModelSelectionPolicyTest` with the Android unit-test task.

`AgentStableAutoRouteDeviceTest` exercises ten isolated conversation scopes with synthetic
targets, persisted target updates, stale-turn rejection and cleanup. It does not contact live providers.

## Real Device Acceptance

1. With Codex and DeepSeek both ready, open a new conversation showing Auto / Codex.
   Send a simple query. Header, planned connector, dispatched connector and receipt must all identify Codex.
2. Repeat with DeepSeek having better historical latency; healthy Codex must remain selected.
3. Make Codex unavailable or exhaust its capacity. Verify a fresh scored alternative and matching header.
4. Exercise immediate dispatch failure and asynchronous failure separately. Verify bounded recovery,
   no switch back to an attempted provider during dispatch refresh, and no duplicate external effects.
5. Restore Codex while Auto shows DeepSeek. A new message stays on the currently displayed DeepSeek.
6. In ten separate conversations, verify independent selections and reject late updates from an old turn.
7. Verify manual model selection and explicit teams are unchanged. With no eligible provider, stop with
   the existing unavailable/error state rather than bypassing a hard gate.

Unit tests are not proof of live MQTT delivery or real-provider failover. Record those results separately.
