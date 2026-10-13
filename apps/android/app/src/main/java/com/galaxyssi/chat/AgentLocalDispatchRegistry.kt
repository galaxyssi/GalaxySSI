package com.galaxyssi.chat

import java.util.concurrent.ConcurrentHashMap

internal data class AgentLocalDispatchIdentity(
    val sourceMessageId: Long,
    val contactId: String,
    val conversationId: String,
    val turnId: String,
    val taskId: String,
    val actionId: String
) {
    init {
        require(sourceMessageId > 0 && listOf(contactId, conversationId, turnId, taskId, actionId).none(String::isBlank))
    }
}

/** Exact dispatch ownership; cancelling a team member must not poison its siblings' shared task. */
internal object AgentLocalDispatchRegistry {
    private val active = ConcurrentHashMap<AgentLocalDispatchIdentity, AgentLocalDispatchLease>()

    fun register(identity: AgentLocalDispatchIdentity,
        cancellation: AgentNativeToolCancellationToken = AgentNativeToolCancellationToken.NONE): AgentLocalDispatchLease {
        val lease = AgentLocalDispatchLease(identity.taskId, cancellation) { active.remove(identity, it) }
        if (active.putIfAbsent(identity, lease) != null) {
            lease.close()
            error("Local dispatch is already active")
        }
        return lease
    }

    fun cancelExact(identity: AgentLocalDispatchIdentity): Boolean = active[identity]?.cancel() ?: false
    internal fun current(identity: AgentLocalDispatchIdentity): AgentLocalDispatchLease? = active[identity]

    internal fun activeCount() = active.size
}
