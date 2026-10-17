package com.galaxyssi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/** Synthetic receipts exercise the production checkpoint path without changing device state. */
internal fun verifyUnverifiedOutcomeRecovery(context: Context): JSONObject {
    val scope = "outcome-recovery-${UUID.randomUUID()}"
    val store = SharedPreferencesAgentSessionStore(context, scope)
    val checks = mutableListOf<String>()
    fun verify(name: String, condition: Boolean) { check(condition) { name }; checks += name }
    val tool = AgentAndroidSystemNativeTools.AUDIO_VOLUME_SET
    val readTool = AgentAndroidSystemNativeTools.AUDIO_STATUS
    val screen = ScreenContext("com.galaxyssi.chat", pageTitle = "Synthetic acceptance")
    val action = AgentAction("effect", AgentActionKind.CALL_NATIVE_TOOL, tool, AgentRisk.LOW,
        AgentActionStatus.COMPLETED, "Synthetic effect", mapOf("tool_id" to tool,
            INTERNAL_CONVERSATION_ID to scope, INTERNAL_TURN_ID to scope),
        evidence = """{"state_verified":false,"requested_level":4,"current_level":3}""")
    val result = AgentActionResult(action.id, true, "Unverified", mapOf("goal_status" to "unknown"))
    val targets = listOf(AgentCallableTarget("synthetic", "Synthetic provider", AgentConnectorKind.MODEL,
        AgentConnectorStatus.AVAILABLE, listOf(AgentCapability.REASONING)))
    val request = AgentRequest("Verify synthetic volume outcome", screen, targets, memories = emptyList(),
        executionTurnId = scope, conversationContext = AgentConversationContext(scope, "", emptyList(), false),
        runtimeContext = AgentRuntimeContextBuilder.build(scope, "Synthetic test", screen, PermissionMode.FULL_ACCESS,
            false, false, emptyList(), emptyList()))
    val provider = AgentAction("provider", AgentActionKind.CALL_CONNECTOR, "Synthetic provider", AgentRisk.LOW,
        AgentActionStatus.PROPOSED, "No model invocation", mapOf("connector_id" to "synthetic", "model_id" to "fixture-model"))
    val plan = AgentPlan(request.goal, screen, emptyList(), listOf(action), planId = scope)
    val descriptor = AgentNativeToolDescriptor(readTool, "1.0.0", "Read", "Synthetic observation",
        AgentNativeToolLocation.PHONE, AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(),
        AgentNativeToolRisk.LOW, idempotency = AgentNativeToolIdempotency.IDEMPOTENT, effect = AgentNativeToolEffect.READ_ONLY)
    val report = JSONObject().put("scope", scope).put("started_at_ms", System.currentTimeMillis())
    try {
        val recovered = requireNotNull(AgentUnverifiedOutcomeRecovery.create(plan, action, result, request, provider))
        val snapshot = AgentSessionSnapshot(scope, AgentPhase.PLANNING, plan.goal, screen, recovered,
            emptyList(), result, updatedAtMillis = System.currentTimeMillis())
        store.save(snapshot)
        val restored = SharedPreferencesAgentSessionStore(context, scope).load()!!.currentPlan!!
        val connector = restored.actions.single()
        verify("restored original receipt and selected model", restored.actionHistory.single().evidence == action.evidence &&
            connector.parameters["model_id"] == "fixture-model")
        verify("no native effect queued again", restored.actions.all { it.kind == AgentActionKind.CALL_CONNECTOR })
        fun gate(history: List<AgentAction>, proposed: List<AgentAction>) =
            AgentUnverifiedOutcomeRecovery.observationViolation(connector, history, proposed) {
                descriptor.takeIf { candidate -> candidate.id == it }
            }
        verify("completion and mutation blocked before observation",
            gate(restored.actionHistory, emptyList()) != null && gate(restored.actionHistory, listOf(action)) != null)
        val observed = action.copy(id = "observation", target = readTool,
            parameters = action.parameters + ("tool_id" to readTool), evidence = """{"current_level":3}""")
        verify("fresh read-only observation permits next decision",
            gate(restored.actionHistory, listOf(observed)) == null &&
                gate(restored.actionHistory + observed, emptyList()) == null)
        store.save(snapshot.copy(phase = AgentPhase.CANCELLED))
        verify("cancelled checkpoint stays cancelled after reload",
            SharedPreferencesAgentSessionStore(context, scope).load()?.phase == AgentPhase.CANCELLED)
        report.put("passed", true).put("checks", JSONArray(checks))
    } finally {
        store.clear()
        report.put("cleanup_verified", store.load() == null)
    }
    return report.put("completed_at_ms", System.currentTimeMillis()).put("validation_layer",
        "Android durable checkpoint and admission with synthetic receipts; no model or device mutation")
}
