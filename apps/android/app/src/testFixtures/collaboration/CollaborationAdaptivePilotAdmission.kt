package com.galaxyssi.chat

import org.json.JSONObject

/** Test-only reservation. It observes production prompts; it never replaces them or fixes a DAG. */
internal class CollaborationAdaptivePilotAdmission(
    private val plan: CollaborationAdaptivePilotPlan, private val group: String, private val run: String, private val turn: String,
    private val deadlineElapsed: Long, private val nowElapsed: () -> Long,
    private val checkpoint: () -> AgentTeamExecutionCheckpoint?, private val persist: (JSONObject) -> Unit
) {
    private val prepared = mutableMapOf<String, AgentTeamMemberExecutionContext>()
    private val admitted = mutableSetOf<String>()
    private var closed = false

    @Synchronized fun count() = admitted.size
    @Synchronized fun exhausted() = admitted.size >= plan.maximumDispatches
    @Synchronized fun close() { closed = true }

    @Synchronized fun observeResources(context: AgentTeamMemberExecutionContext, nowUnixMillis: Long): AgentTeamMemberExecutionContext {
        check(prepared[context.request.idempotencyKey] == context) { "Resource observation requires the prepared assignment" }
        check(context.member.memberId !in admitted) { "This dispatch is already reserved" }
        val current = nowElapsed()
        val observation = AgentTeamResourceObservation.capture(context, AgentTeamResourceObservation.Unit.PHONE_DISPATCH,
            plan.maximumDispatches.toLong(), admitted.size.toLong(), nowUnixMillis,
            (deadlineElapsed - current).coerceAtLeast(0), closed || exhausted() || current >= deadlineElapsed)
        return context.copy(resourceObservation = observation).also { prepared[context.request.idempotencyKey] = it }
    }

    @Synchronized fun prepare(context: AgentTeamMemberExecutionContext) {
        check(!closed && nowElapsed() < deadlineElapsed) { "Adaptive trial admission closed" }
        check(!exhausted()) { "Adaptive trial phone-dispatch envelope exhausted" }
        val current = requireNotNull(checkpoint()) { "Missing production checkpoint" }
        check(current.request.runId == run && current.request.conversationId == group && current.request.messageId == turn &&
            current.request.goal == plan.goal && current.request.taskId == context.request.taskId) { "Adaptive trial parent changed" }
        val member = current.definition.members.single { it.memberId == context.member.memberId }
        check(member == context.member && context.request.parentRunId == run && context.request.conversationId == group &&
            context.request.messageId == turn && context.request.goal == plan.goal &&
            context.request.runId == stableAgentTeamMemberRunId(run, member.memberId)) { "Adaptive assignment is not owned by the production graph" }
        check(member.deliveryMode != AgentDeliveryMode.IGNORE && member.agentId == plan.targetId && member.context["collaboration_model_id"] == plan.selection.modelId &&
            member.context[CollaborationReasoningSelection.KEY] == plan.selection.reasoningEffort.wireValue &&
            plan.matchesExecution(member, current.definition)) {
            "Trial must retain its frozen execution mode and selected model"
        }
        check(!context.handoff.truncated && context.handoff.dependencies.none { it.outputTruncated }) { "Adaptive trial input was truncated" }
        val key = context.request.idempotencyKey
        check(key == "${current.request.idempotencyKey}:${member.memberId}" && key !in prepared && member.memberId !in admitted) {
            "Adaptive trial cannot repeat an already prepared assignment"
        }
        prepared[key] = context
    }

    @Synchronized fun admit(action: AgentAction): AgentAction {
        check(!closed && nowElapsed() < deadlineElapsed && !exhausted()) { "Adaptive trial admission exhausted or closed" }
        val p = action.parameters
        val context = requireNotNull(prepared[p["idempotency_key"]]) { "Adaptive dispatch was not prepared" }
        val current = requireNotNull(checkpoint())
        check(current.definition.members.singleOrNull { it.memberId == context.member.memberId } == context.member &&
            current.request.runId == run && current.request.messageId == turn && current.request.conversationId == group &&
            current.request.goal == plan.goal && current.request.taskId == context.request.taskId &&
            plan.matchesExecution(context.member, current.definition) &&
            context.request.idempotencyKey == "${current.request.idempotencyKey}:${context.member.memberId}") {
            "Production graph changed before trial dispatch"
        }
        check(action.kind == AgentActionKind.CALL_CONNECTOR && p["connector_id"] == plan.targetId &&
            p["agent_model_id"] == plan.selection.modelId && p["manual_model_id"] == plan.selection.modelId &&
            p["agent_reasoning_effort"] == plan.selection.reasoningEffort.wireValue && p["manual_target_locked"] == "true" &&
            p[MANAGED_AGENT_TEAM_ACTION_PARAMETER] == "true" && p["agent_instance_id"] == context.member.memberId &&
            p["_galaxyssi_conversation_id"] == group && p["_galaxyssi_turn_id"] == turn && p["_galaxyssi_task_id"] == context.request.taskId) {
            "Adaptive trial dispatch identity or model changed"
        }
        val prompt = requireNotNull(action.managedTeamAssignmentPrompt())
        if (plan.singleAgent) check(prompt.contains(plan.goal)) {
            "Single-agent production prompt omitted part of the original task; no silent truncation"
        }
        context.resourceObservation?.let {
            check(prompt.contains(it.prompt(context).trim())) { "Production prompt omitted the host resource observation" }
        }
        check(context.member.memberId !in admitted)
        admitted.add(context.member.memberId)
        persist(JSONObject().put("execution_mode", plan.executionMode)
            .put("node_id", context.member.memberId).put("person_id", context.member.context[CollaborationResearchWorkflow.PERSON])
            .put("stage", context.member.context[CollaborationResearchWorkflow.STAGE])
            .put("assignment", context.member.objective).put("owner_run_id", context.request.runId).put("parent_run_id", run)
            .put("conversation_id", group).put("turn_id", turn).put("task_id", context.request.taskId)
            .put("idempotency_key", context.request.idempotencyKey)
            .put("source_message_id", AgentTeamDispatchIds.sourceMessageId("member:${context.request.idempotencyKey}"))
            .put("requested_model", plan.selection.modelId).put("requested_reasoning_effort", plan.selection.reasoningEffort.wireValue)
            .put("round", current.request.context[CollaborationGoalLoop.ROUND]?.toString() ?: "0")
            .put("prompt_sha256", CollaborationRemotePilotDispatch.sha256(prompt.toByteArray(Charsets.UTF_8)))
            .put("prompt_characters", prompt.length).put("prompt_replaced_by_harness", false)
            .put("resource_observation", context.resourceObservation?.json(context) ?: JSONObject.NULL)
            .put("admitted_elapsed_ms", nowElapsed()).put("accounting_scope", "phone_delegate_dispatch_not_provider_request"))
        return action
    }
}
