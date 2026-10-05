package com.galaxyssi.chat

import java.security.MessageDigest
import org.json.JSONObject

/** Reserves each phone-side delegate dispatch before I/O; this is NOT an API-request budget. */
internal class CollaborationRemotePilotDispatch(
    private val plan: CollaborationRemoteExecutionPolicy,
    private val definition: AgentTeamDefinition,
    private val group: String,
    private val run: String,
    private val turn: String,
    private val deadlineElapsed: Long,
    private val nowElapsed: () -> Long,
    private val persist: (JSONObject) -> Unit
) {
    private val prepared = mutableMapOf<String, AgentTeamMemberExecutionContext>()
    private val admitted = mutableSetOf<String>()
    private var closed = false

    @Synchronized fun prepare(context: AgentTeamMemberExecutionContext) {
        check(!closed && nowElapsed() < deadlineElapsed) { "Remote pilot admission closed" }
        val expected = definition.members.single { it.memberId == context.member.memberId }
        check(context.member == expected && context.request.parentRunId == run && context.request.conversationId == group &&
            context.request.messageId == turn) { "Remote pilot assignment identity changed" }
        val key = context.request.idempotencyKey
        check(key.isNotBlank() && key !in prepared && context.member.memberId !in admitted) { "Remote pilot assignment cannot be repeated" }
        plan.prompt(context)
        prepared[key] = context
    }

    @Synchronized fun admit(action: AgentAction): AgentAction {
        check(!closed && nowElapsed() < deadlineElapsed) { "Remote pilot deadline reached before dispatch" }
        val p = action.parameters
        val context = requireNotNull(prepared[p["idempotency_key"]]) { "Remote pilot dispatch was not prepared" }
        check(action.kind == AgentActionKind.CALL_CONNECTOR && p["connector_id"] == plan.targetId &&
            p["agent_model_id"] == plan.selection.modelId && p["manual_model_id"] == plan.selection.modelId &&
            p["agent_reasoning_effort"] == plan.selection.reasoningEffort.wireValue && p["manual_target_locked"] == "true" &&
            p[MANAGED_AGENT_TEAM_ACTION_PARAMETER] == "true" && p["agent_instance_id"] == context.member.memberId &&
            p["_galaxyssi_conversation_id"] == group && p["_galaxyssi_turn_id"] == turn &&
            p["_galaxyssi_task_id"] == context.request.taskId) { "Remote pilot dispatch controls changed" }
        check(context.member.memberId !in admitted && admitted.size < definition.members.size) { "Remote pilot dispatch allowance exhausted" }
        val prompt = plan.prompt(context)
        val person = requireNotNull(context.member.context[CollaborationResearchWorkflow.PERSON])
        check(person in setOf("analyst", "reviewer")) { "Unknown remote pilot person" }
        // Consume before persisting; if disk write fails, this object cannot dispatch the same node again.
        admitted.add(context.member.memberId)
        persist(JSONObject().put("node_id", context.member.memberId)
            .put("person_id", context.member.context[CollaborationResearchWorkflow.PERSON])
            .put("transport_instance_id", person)
            .put("owner_run_id", context.request.runId).put("parent_run_id", run).put("turn_id", turn)
            .put("conversation_id", group).put("task_id", context.request.taskId)
            .put("idempotency_key", context.request.idempotencyKey)
            .put("source_message_id", AgentTeamDispatchIds.sourceMessageId("member:${context.request.idempotencyKey}"))
            .put("target_id", plan.targetId).put("requested_model", plan.selection.modelId)
            .put("requested_reasoning_effort", plan.selection.reasoningEffort.wireValue)
            .put("prepared_prompt_sha256", sha256(prompt.toByteArray()))
            .put("prepared_prompt_characters", prompt.length).put("admitted_elapsed_ms", nowElapsed())
            .put("accounting_scope", "phone_delegate_dispatch_not_provider_request"))
        // The graph keeps distinct node/owner/source identities. Only the remote conversation
        // namespace follows the person, so sequential work can reuse that person's context.
        return action.copy(parameters = p + mapOf("prompt" to prompt, "agent_instance_id" to person))
    }

    @Synchronized fun close() { closed = true }

    companion object {
        fun sha256(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
    }
}
