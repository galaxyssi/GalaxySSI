package com.galaxyssi.chat

const val AGENT_RUN_EVENT_PROTOCOL = "galaxyssi.agent-run-event.v1"
const val AGENT_RUN_EVENT_SCHEMA_VERSION = 1

data class AgentRunRootIdentity(
    val clientRouteId: String,
    val conversationId: String,
    val goalId: String,
    val taskId: String,
    val runId: String
)

object AgentRunKernelContract {
    fun canonical(event: AgentRunControlEvent): AgentRunControlEvent {
        require(event.protocolId == AGENT_RUN_EVENT_PROTOCOL) {
            "Unsupported Run event protocol: ${event.protocolId}"
        }
        require(event.schemaVersion == AGENT_RUN_EVENT_SCHEMA_VERSION) {
            "Unsupported Run event schema: ${event.schemaVersion}"
        }
        require(event.eventId.isNotBlank()) { "Run event id must not be blank" }
        require(event.runId.isNotBlank() && event.taskId.isNotBlank()) {
            "Run and task ids must not be blank"
        }
        require(event.agentId.isNotBlank()) { "Run event agent id must not be blank" }
        val eventId = event.eventId.trim()
        val taskId = event.taskId.trim()
        val deviceId = event.deviceId.trim().ifBlank { "local" }
        val messageId = event.messageId.trim()
        val stepId = event.stepId.trim()
        val toolCallId = event.toolCallId.trim()
        return event.copy(
            eventId = eventId,
            taskId = taskId,
            runId = event.runId.trim(),
            agentId = event.agentId.trim(),
            idempotencyKey = event.idempotencyKey.trim().ifBlank { eventId },
            clientRouteId = event.clientRouteId.trim().ifBlank { deviceId },
            conversationId = event.conversationId.trim().ifBlank { "conversation:$taskId" },
            goalId = event.goalId.trim().ifBlank { taskId },
            turnId = event.turnId.trim().ifBlank { messageId.ifBlank { "turn:$taskId" } },
            actionId = event.actionId.trim().ifBlank {
                toolCallId.ifBlank { stepId.ifBlank { eventId } }
            },
            messageId = messageId,
            stepId = stepId,
            toolCallId = toolCallId,
            deviceId = deviceId
        )
    }

    fun rootIdentity(event: AgentRunControlEvent): AgentRunRootIdentity {
        val canonical = canonical(event)
        return AgentRunRootIdentity(
            clientRouteId = canonical.clientRouteId,
            conversationId = canonical.conversationId,
            goalId = canonical.goalId,
            taskId = canonical.taskId,
            runId = canonical.runId
        )
    }

    fun requireSameRoot(
        expected: AgentRunControlEvent,
        actual: AgentRunControlEvent
    ) {
        val expectedIdentity = rootIdentity(expected)
        val actualIdentity = rootIdentity(actual)
        require(expectedIdentity == actualIdentity) {
            "Run root identity changed: expected=$expectedIdentity actual=$actualIdentity"
        }
    }

    fun requireIdempotentReplay(
        expected: AgentRunControlEvent,
        actual: AgentRunControlEvent
    ) {
        val first = canonical(expected)
        val replay = canonical(actual)
        require(first.idempotencyKey == replay.idempotencyKey) {
            "Run event idempotency keys do not match"
        }
        require(
            first.rootIdentityFields() == replay.rootIdentityFields() &&
                first.turnId == replay.turnId &&
                first.actionId == replay.actionId &&
                first.messageId == replay.messageId &&
                first.stepId == replay.stepId &&
                first.toolCallId == replay.toolCallId &&
                first.agentId == replay.agentId &&
                first.deviceId == replay.deviceId &&
                first.type == replay.type &&
                first.payload == replay.payload
        ) {
            "Run event idempotency key was reused with different content: ${first.idempotencyKey}"
        }
    }

    private fun AgentRunControlEvent.rootIdentityFields() = listOf(
        clientRouteId,
        conversationId,
        goalId,
        taskId,
        runId
    )
}
