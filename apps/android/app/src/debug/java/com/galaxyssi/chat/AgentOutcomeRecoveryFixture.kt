package com.galaxyssi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/** The effect is synthetic; only the observation reads actual Android state. */
internal fun verifyUnverifiedOutcomeRecovery(context: Context): JSONObject {
    val scope = "outcome-recovery-${UUID.randomUUID()}"
    val store = SharedPreferencesAgentSessionStore(context, scope)
    val checks = mutableListOf<String>()
    fun verify(name: String, condition: Boolean) { check(condition) { name }; checks += name }
    val tool = AgentAndroidSystemNativeTools.AUDIO_VOLUME_SET
    val readTool = AgentAndroidSystemNativeTools.AUDIO_STATUS
    val definitions = AgentAndroidSystemNativeTools.definitions(context)
    val effect = definitions.single { it.descriptor.id == tool }.let { AgentNativeToolDefinition(
        descriptor = it.descriptor.copy(outputSchema = AgentNativeJsonSchema.objectSchema()),
        executor = AgentNativeToolExecutor { AgentNativeToolExecutionResult.success(mapOf("state_verified" to false)) },
        effectRecoveryProvider = it.effectRecoveryProvider) }
    val registry = AgentNativeToolRegistry().registerAll(definitions.filterNot { it.descriptor.id == tool } + effect)
    val call = AgentNativeToolInvocationContext(sessionId = scope, conversationId = scope, turnId = scope,
        invocationId = "synthetic-effect", idempotencyKey = "synthetic-effect",
        grantedPermissions = effect.descriptor.requiredPermissions.mapTo(linkedSetOf()) { it.id },
        grantedConsents = effect.descriptor.requiredConsents.mapTo(linkedSetOf()) { it.id })
    val synthetic = registry.invoke(tool, mapOf("stream" to "music", "percent" to 1), call)
    check(synthetic.isSuccess) { "Synthetic effect contract failed: ${synthetic.error?.code}" }
    val screen = ScreenContext("com.galaxyssi.chat", pageTitle = "Synthetic acceptance")
    val action = AgentAction("effect", AgentActionKind.CALL_NATIVE_TOOL, tool, AgentRisk.LOW,
        AgentActionStatus.COMPLETED, "Synthetic effect", mapOf("tool_id" to tool,
            INTERNAL_CONVERSATION_ID to scope, INTERNAL_TURN_ID to scope),
        evidence = AgentNativeJsonCodec.stringify(AgentRecoveryObservationEvidence.attach(synthetic.output,
            synthetic, call, effect.descriptor)))
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
    val report = JSONObject().put("scope", scope).put("started_at_ms", System.currentTimeMillis())
    try {
        verify("actual audio status contract is read-only", !registry.lookup(readTool)!!.descriptor.requiresEffectClaim)
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
            AgentUnverifiedOutcomeRecovery.observationViolation(connector, history, proposed) { registry.lookup(it)?.descriptor }
        verify("completion and mutation blocked before observation",
            gate(restored.actionHistory, emptyList()) != null && gate(restored.actionHistory, listOf(action)) != null)
        val readContext = call.copy(invocationId = "actual-observation", idempotencyKey = null)
        val readResult = registry.invoke(readTool, emptyMap(), readContext)
        verify("actual Android read succeeded", readResult.isSuccess)
        val observed = action.copy(id = "observation", target = readTool,
            parameters = action.parameters + ("tool_id" to readTool), evidence = AgentNativeJsonCodec.stringify(
                AgentRecoveryObservationEvidence.attach(readResult.output, readResult, readContext, registry.lookup(readTool)!!.descriptor)))
        verify("fresh scoped observation permits next decision", gate(restored.actionHistory, listOf(observed)) == null &&
            gate(restored.actionHistory + observed, emptyList()) == null)
        fun changed(edit: (JSONObject) -> Unit) = observed.copy(evidence = JSONObject(observed.evidence).apply(edit).toString())
        val replay = changed { it.getJSONObject(AgentRecoveryObservationEvidence.KEY).put("replayed", true) }
        verify("replayed observation rejected", gate(restored.actionHistory + replay, listOf(action)) != null)
        val foreign = changed { it.getJSONObject(AgentRecoveryObservationEvidence.KEY).put("turn_id", "other") }
        verify("other turn receipt rejected", gate(restored.actionHistory + foreign, emptyList()) != null)
        val unrelated = changed { it.getJSONObject("streams").remove("music") }
        verify("missing affected subject rejected", gate(restored.actionHistory + unrelated, listOf(action)) != null)
        val failed = observed.copy(id = "later", status = AgentActionStatus.FAILED)
        verify("new failure cannot reuse older success", gate(restored.actionHistory + listOf(observed, failed), listOf(action)) != null)
        for (minimal in listOf(false, true)) {
            val compact = AgentSessionPersistencePolicy.compactRecoveryPlan(restored, connector.id, minimal)
            verify("origin contract survives compact checkpoint $minimal",
                gate(compact.actionHistory + observed, emptyList()) == null)
        }
        store.save(snapshot.copy(phase = AgentPhase.CANCELLED))
        verify("cancelled checkpoint stays cancelled after reload",
            SharedPreferencesAgentSessionStore(context, scope).load()?.phase == AgentPhase.CANCELLED)
        report.put("passed", true).put("checks", JSONArray(checks)).put("actual_read_count", 1)
            .put("device_mutation_count", 0).put("model_call_count", 0)
    } finally {
        store.clear()
        report.put("cleanup_verified", store.load() == null)
    }
    return report.put("completed_at_ms", System.currentTimeMillis()).put("validation_layer",
        "Synthetic effect with production adapter query, durable checkpoint, actual Android read and host receipt; no device mutation")
}
