package com.galaxyssi.chat

/** The reply binding must exist before a queued request can reach a fast remote Agent. */
internal object AgentConnectorDispatchBinding {
    fun publish(
        delivery: AgentPendingDelivery?,
        register: (AgentPendingDelivery) -> Unit,
        retire: (Long) -> Unit,
        send: () -> Boolean
    ): Boolean {
        delivery?.let(register)
        val accepted = try {
            send()
        } catch (failure: Throwable) {
            delivery?.let { runCatching { retire(it.sourceMessageId) } }
            throw failure
        }
        if (!accepted) delivery?.let { retire(it.sourceMessageId) }
        return accepted
    }
}
