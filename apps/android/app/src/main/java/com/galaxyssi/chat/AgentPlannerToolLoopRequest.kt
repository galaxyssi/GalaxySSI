package com.galaxyssi.chat

/** Planning is part of the current task; it does not own a new file workspace. */
internal object AgentPlannerToolLoopRequest {
    fun create(
        request: AgentRequest,
        settings: AgentModelPlannerSettings,
        messages: List<AgentModelMessage>,
        catalog: List<AgentNativeToolDescriptor>,
        eventSink: AgentModelToolLoopEventSink = AgentModelToolLoopEventSink.NONE,
        cancellationToken: AgentNativeToolCancellationToken = AgentNativeToolCancellationToken.NONE
    ): AgentModelToolLoopRequest {
        val sessionId = request.runtimeContext.sessionId
        val conversationId = request.conversationContext.conversationId.ifBlank { sessionId }
        // Matches MobileNativeAgent.startExecutionLoop's task/turn fallback.
        val turnId = request.executionTurnId.trim().ifBlank { sessionId }
        require(request.planningRevision > 0) { "Planning revision must be positive" }
        val inputIdentity = AgentNativeJsonCodec.sha256(mapOf("goal" to request.goal,
            "revision" to request.planningRevision, "reason" to request.replanReason,
            "requirements" to request.completionRequirements?.toString(),
            "history" to request.executionHistory.map { mapOf("id" to it.id, "status" to it.status.name,
                "kind" to it.kind.name, "target" to it.target, "parameters" to it.parameters) }))
        return AgentModelToolLoopRequest(
            sessionId = sessionId,
            conversationId = conversationId,
            turnId = turnId,
            taskId = turnId,
            workspaceId = AgentWorkspaceScope.id(conversationId, sessionId),
            loopId = "planner-$inputIdentity",
            recoveryInputIdentity = inputIdentity,
            messages = messages,
            budget = AgentModelPlannerToolLoopBudgetPolicy.compile(settings),
            eventSink = eventSink,
            cancellationToken = cancellationToken,
            grantedPermissions = catalog.flatMap { it.requiredPermissions }
                .filter { it.required }.mapTo(linkedSetOf()) { it.id }
        )
    }
}
