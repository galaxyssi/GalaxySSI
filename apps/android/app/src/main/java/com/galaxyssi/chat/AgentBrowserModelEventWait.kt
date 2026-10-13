package com.galaxyssi.chat

internal class AgentBrowserModelEventWaitResolver(
    private val load: (String) -> AgentBrowserUserRequest?,
    private val ownsRun: (AgentBrowserUserRequest) -> Boolean,
    private val waitingMessage: String = "Waiting for you to finish in the browser and return control; the original task is saved.",
    private val commitObservation: (AgentBrowserUserRequest) -> Unit = {}
) : AgentModelToolEventWaitResolver {
    override fun supports(toolId: String) = toolId == AgentInteractiveBrowserTools.ACT

    override fun observationCommitted(request: AgentModelToolLoopRequest, call: AgentModelToolCall,
        result: AgentNativeToolResult) {
        val resolved = resolve(request, call, result) as? AgentModelToolEventWait.Resolved ?: return
        val event = result.metadata["external_event"] as? Map<*, *> ?: return
        if (event != resolved.result.metadata["external_event"]) return
        val key = result.output["host_wait_key"] as? String ?: return
        val record = load(key) ?: return
        if (record.settled && event["event_id"] == AgentNativeJsonCodec.sha256(listOf(record.key, record.generation)))
            commitObservation(record)
    }

    override fun resolve(request: AgentModelToolLoopRequest, call: AgentModelToolCall,
        result: AgentNativeToolResult): AgentModelToolEventWait? {
        if (!supports(call.toolId) || call.arguments["operation"] != "request_user_control" ||
            !result.isSuccess || result.output["durable_resume_available"] != true) return null
        val key = result.output["host_wait_key"] as? String ?: return null
        val generation = result.output["host_wait_generation"] as? String ?: return null
        val record = load(key)
        val context = AgentNativeToolInvocationContext(invocationId = result.receipt.invocationId,
            sessionId = request.sessionId, conversationId = request.conversationId, turnId = request.turnId,
            callerId = request.callerId, attributes = mapOf("task_id" to request.taskId,
                "workspace_id" to request.workspaceId))
        if (record == null || record.generation != generation || !record.sameOwner(context) ||
            record.modelLoopId != request.loopId || record.browserSessionId != call.arguments["session_id"] ||
            record.pageId != call.arguments["page_id"] || !ownsRun(record)) {
            return AgentModelToolEventWait.Resolved(result.copy(metadata = result.metadata + mapOf(
                "external_event" to mapOf("kind" to "browser_control_unobserved", "control_owner" to "unknown",
                    "code" to "browser_wait_binding_changed", "goal_terminal" to false, "requires_observation" to true,
                    "message" to "The original handoff cannot be verified. No other event or authentication state was consumed. Inspect the browser and diagnose before another mutation."))))
        }
        val eventId = AgentNativeJsonCodec.sha256(listOf(record.key, record.generation))
        if (record.state == "interrupted") return AgentModelToolEventWait.Resolved(result.copy(
            metadata = result.metadata + mapOf("external_event" to mapOf(
                "event_id" to eventId, "kind" to "browser_control_interrupted", "code" to record.interruptionCode,
                "control_owner" to "unknown", "authentication_verified" to false, "goal_terminal" to false,
                "requires_observation" to true,
                "message" to AgentBrowserInterruptionPolicy.message(record.interruptionCode)))))
        return if (record.state != "returned") AgentModelToolEventWait.Pending(eventId, waitingMessage)
        else AgentModelToolEventWait.Resolved(result.copy(metadata = result.metadata + mapOf(
            "external_event" to mapOf("event_id" to eventId, "kind" to "browser_control_returned",
                "control_owner" to "agent", "authentication_verified" to false, "requires_observation" to true,
                "message" to "User returned control after the recorded handoff. Observe the current page before deciding whether authentication or the task succeeded."))))
    }
}
