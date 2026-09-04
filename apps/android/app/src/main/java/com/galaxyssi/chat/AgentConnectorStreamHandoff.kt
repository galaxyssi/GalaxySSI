package com.galaxyssi.chat

internal object AgentConnectorStreamHandoff {
    inline fun <T> persistThenRetire(
        persistFinal: () -> T,
        retireLiveStream: () -> Unit
    ): T {
        val result = persistFinal()
        retireLiveStream()
        return result
    }
}
