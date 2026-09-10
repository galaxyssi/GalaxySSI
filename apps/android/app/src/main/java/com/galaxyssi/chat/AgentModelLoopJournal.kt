package com.galaxyssi.chat

/** A journal failure must never fall through to a different executable plan. */
class AgentModelLoopRecoveryException(message: String, cause: Throwable? = null) : IllegalStateException(message, cause)

data class AgentModelLoopScope(val session: String, val conversation: String, val turn: String,
    val task: String, val workspace: String, val caller: String, val loop: String) {
    fun value(): Map<String, String> = linkedMapOf("session" to session, "conversation" to conversation,
        "turn" to turn, "task" to task, "workspace" to workspace, "caller" to caller, "loop" to loop)
    val digest: String get() = AgentNativeJsonCodec.sha256(value())
    companion object {
        fun from(request: AgentModelToolLoopRequest): AgentModelLoopScope {
            require(request.loopId.isNotBlank()) { "A durable model loop requires a stable loop id" }
            return AgentModelLoopScope(request.sessionId, request.conversationId, request.turnId,
                request.taskId, request.workspaceId, request.callerId, request.loopId)
        }
    }
}

interface AgentModelLoopRecords {
    fun read(operation: String): String?
    fun write(operation: String, json: String)
}

interface AgentModelLoopJournal {
    fun hasRecords(scope: AgentModelLoopScope): Boolean
    suspend fun <T> withLease(scope: AgentModelLoopScope, block: suspend (AgentModelLoopRecords) -> T): T
}

class InMemoryAgentModelLoopJournal : AgentModelLoopJournal {
    private val active = mutableSetOf<AgentModelLoopScope>()
    private val records = mutableMapOf<Pair<AgentModelLoopScope, String>, String>()
    @Synchronized override fun hasRecords(scope: AgentModelLoopScope) = records.containsKey(scope to "initial")
    override suspend fun <T> withLease(scope: AgentModelLoopScope, block: suspend (AgentModelLoopRecords) -> T): T {
        synchronized(this) {
            if (!active.add(scope)) throw AgentModelLoopRecoveryException("model_loop_busy")
        }
        try {
            return block(object : AgentModelLoopRecords {
                override fun read(operation: String) = synchronized(this@InMemoryAgentModelLoopJournal) {
                    records[scope to operation]
                }
                override fun write(operation: String, json: String) = synchronized(this@InMemoryAgentModelLoopJournal) {
                    val previous = records.putIfAbsent(scope to operation, json)
                    if (previous != null && previous != json) throw AgentModelLoopRecoveryException("model_loop_record_changed")
                }
            })
        } finally { synchronized(this) { active.remove(scope) } }
    }
}
