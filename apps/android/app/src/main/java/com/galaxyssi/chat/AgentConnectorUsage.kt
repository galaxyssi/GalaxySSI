package com.galaxyssi.chat

import java.nio.ByteBuffer
import java.security.MessageDigest

/** An idempotent projection of one authenticated execution's final usage. */
internal data class AgentConnectorUsage(
    val key: String,
    val inputTokens: Long,
    val outputTokens: Long,
    val costMicros: Long
) {
    init {
        require(key.matches(Regex("[a-f0-9]{64}"))) { "Invalid connector usage identity" }
        require(inputTokens >= 0 && outputTokens >= 0 && costMicros >= 0)
    }

    val digest: String get() = MessageDigest.getInstance("SHA-256").digest(
        ByteBuffer.allocate(24).putLong(inputTokens).putLong(outputTokens).putLong(costMicros).array()
    ).joinToString("") { "%02x".format(it) }

    fun applyTo(previous: AgentConversation): AgentConversation = previous.copy(
        inputTokens = add(previous.inputTokens, inputTokens),
        outputTokens = add(previous.outputTokens, outputTokens),
        costMicros = add(previous.costMicros, costMicros)
    )

    companion object {
        fun from(response: AgentConnectorResponse) = AgentConnectorUsage(
            AgentConnectorResponseCodec.identity(response),
            response.inputTokens.coerceAtLeast(0), response.outputTokens.coerceAtLeast(0),
            response.costMicros.coerceAtLeast(0)
        )

        private fun add(previous: Long, increment: Long): Long {
            val limit = Long.MAX_VALUE / 2
            val current = previous.coerceIn(0, limit)
            return current + increment.coerceIn(0, limit - current)
        }
    }
}
