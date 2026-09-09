package com.galaxyssi.chat

import java.util.UUID

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
        return AgentModelToolLoopRequest(
            sessionId = sessionId,
            conversationId = conversationId,
            turnId = turnId,
            taskId = turnId,
            workspaceId = AgentWorkspaceScope.id(conversationId, sessionId),
            loopId = UUID.randomUUID().toString(),
            messages = messages,
            budget = AgentModelPlannerToolLoopBudgetPolicy.compile(settings),
            eventSink = eventSink,
            cancellationToken = cancellationToken,
            grantedPermissions = catalog.flatMap { it.requiredPermissions }
                .filter { it.required }.mapTo(linkedSetOf()) { it.id }
        )
    }
}
