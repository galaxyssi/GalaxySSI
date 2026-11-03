package com.galaxyssi.chat

import org.json.JSONObject

/** Browser events bind to a dispatched node, never to a model-generated browser or task name alone. */
internal object AgentBrowserActionPlanPolicy {
    const val CALLER = "galaxyssi.mobile_agent.plan"

    fun attributes(sessionId: String, plan: AgentPlan?, action: AgentAction): Map<String, String> {
        if (plan?.isSupervisedProjectPlan() != true || action.kind != AgentActionKind.CALL_NATIVE_TOOL) return emptyMap()
        val original = plan.actions.singleOrNull { it.id == action.id } ?: return emptyMap()
        val key = AgentPlanNodeKey.from(sessionId, plan, original) ?: return emptyMap()
        return mapOf("action_plan_id" to plan.planId, "action_plan_revision" to plan.revision.toString(),
            "action_id" to action.id, "action_plan_binding" to AgentNativeJsonCodec.sha256(key.identity()))
    }

    fun eventId(record: AgentBrowserUserRequest) = AgentNativeJsonCodec.sha256(listOf(record.key, record.generation))
    private fun eventMarker(record: AgentBrowserUserRequest) = "browser_external_event:${eventId(record)}"

    fun action(record: AgentBrowserUserRequest, session: AgentSessionSnapshot): AgentAction? {
        val plan = session.currentPlan ?: return null
        if (record.collaborationSourceMessageId != null || record.modelLoopId.isNotBlank() || record.actionPlanBinding.isBlank() ||
            record.callerId != CALLER || plan.planId != record.actionPlanId || !plan.isSupervisedProjectPlan()) return null
        val context = AgentNativeToolInvocationContext(sessionId = record.sessionId,
            conversationId = record.conversationId, turnId = record.turnId, callerId = CALLER,
            attributes = mapOf("workspace_id" to record.workspaceId, "task_id" to record.taskId))
        if (record.scope != AgentInteractiveBrowserTools.scope(context)) return null
        val candidates = (plan.actions + plan.actionHistory).filter { it.id == record.actionId }.filter { action ->
            val key = AgentPlanNodeKey.from(session.sessionId, plan, action) ?: return@filter false
            action.kind == AgentActionKind.CALL_NATIVE_TOOL &&
                plan.checkpoints.lastOrNull { it.actionId == action.id && it.status == AgentCheckpointStatus.ACTIVE }
                    ?.planRevision == record.actionPlanRevision &&
                AgentNativeJsonCodec.sha256(key.identity()) == record.actionPlanBinding &&
                action.parameters["tool_id"] == AgentInteractiveBrowserTools.ACT &&
                runCatching { JSONObject(action.parameters["input_json"].orEmpty()).toNativeObject() }.getOrNull()?.let {
                    it["operation"] == "request_user_control" && it["session_id"] == record.browserSessionId &&
                        it["page_id"] == record.pageId
                } == true
        }
        return candidates.distinct().singleOrNull()?.takeIf {
            (plan.revision == record.actionPlanRevision && it.status in setOf(AgentActionStatus.RUNNING,
                AgentActionStatus.COMPLETED, AgentActionStatus.FAILED)) || observed(record, it)
        }
    }

    fun observed(record: AgentBrowserUserRequest, action: AgentAction) =
        action.evidence.lineSequence().any { it == eventMarker(record) }

    fun receiptRecord(result: AgentActionResult?, load: (String) -> AgentBrowserUserRequest?): AgentBrowserUserRequest? {
        if (result?.success != true || result.metadata["native_tool_id"] != AgentInteractiveBrowserTools.ACT) return null
        val output = runCatching { JSONObject(result.metadata["native_tool_output"].orEmpty()).toNativeObject() }.getOrNull() ?: return null
        if (output["durable_resume_available"] != true) return null
        val key = output["host_wait_key"] as? String ?: return null
        val generation = output["host_wait_generation"] as? String ?: return null
        return load(key)?.takeIf { it.generation == generation && it.actionId == result.actionId &&
            it.actionPlanBinding.isNotBlank() }
    }

    fun observe(record: AgentBrowserUserRequest, action: AgentAction): AgentAction {
        require(record.settled)
        if (observed(record, action)) return action
        val event = AgentNativeJsonCodec.stringify(mapOf("event_id" to eventId(record),
            "kind" to if (record.state == "returned") "browser_control_returned" else "browser_control_interrupted",
            "code" to record.interruptionCode, "control_owner" to if (record.state == "returned") "agent" else "unknown",
            "authentication_verified" to false, "requires_observation" to true, "goal_terminal" to false,
            "message" to "Inspect the existing runtime and browser, observe the current page and verify authentication " +
                "and the original goal before choosing the next action. No browser mutation was replayed."))
        return action.copy(status = AgentActionStatus.COMPLETED,
            result = "External browser observation: $event\nOriginal dispatch: " + action.result,
            evidence = eventMarker(record) + "\nExternal browser observation: $event\nOriginal evidence: " + action.evidence)
    }

    /** Retire stale proposed actions and ask the same reasoning provider for a new batch from observed state. */
    fun continuation(plan: AgentPlan, record: AgentBrowserUserRequest, observed: AgentAction, request: AgentRequest): AgentPlan {
        val connector = (plan.actionHistory + plan.actions).lastOrNull(AgentAction::isSupervisedProjectConnector)
            ?: error("The original supervising provider is missing")
        val retired = plan.copy(actions = plan.actions.map { if (it.id == observed.id) observed else it })
        val revision = plan.revision + 1
        val completed = retired.actions.filter { it.status == AgentActionStatus.COMPLETED }
        val completedById = completed.associateBy(AgentAction::id)
        val base = retired.copy(actions = completed, actionHistory = retired.historyForNextRevision(revision)
            .filterNot { it.id in completedById }, revision = revision, replanCount = plan.replanCount + 1)
        // Build only the new reviewer through the factory. Completed connectors must not deduplicate it.
        val continued = AgentSupervisedProjectLoop.appendReviewer(base.copy(actions = listOf(observed)), connector, request.copy(
            executionHistory = base.actionHistory + completed,
            replanReason = "A host-owned browser event settled. The original tool receipt is unchanged; " +
                "observe the live page before resuming any previously proposed operation."), "browser-${eventId(record).take(20)}")
        val reviewer = continued.actions.single { it.id != observed.id }.let {
            it.copy(parameters = it.parameters + mapOf("depends_on" to completed.joinToString(",", transform = AgentAction::id),
                "use_outputs_from" to (listOf(observed.id) + completed.map(AgentAction::id)).distinct()
                    .joinToString(","))).withPlanRevision(revision)
        }
        // Keep all dispatched parameters byte-for-byte, including the completed dependency chain.
        return continued.copy(actions = completed + reviewer).let { it.copy(validation = AgentPlanValidator.validate(it)) }
    }
}
