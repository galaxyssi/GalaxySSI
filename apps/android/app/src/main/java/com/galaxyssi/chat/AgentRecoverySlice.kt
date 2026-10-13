package com.galaxyssi.chat

import kotlinx.coroutines.CancellationException

/** Covers preparation and durable projection, before the hook defers its final task state. */
internal class AgentRecoverySlice {
    @Volatile var committed = false
        private set
    @Volatile var failure: Exception? = null
        private set

    suspend fun <T> prepareAndCommit(context: AgentTaskContext, block: suspend () -> T): T = try {
        block().also { committed = true }
    } catch (error: CancellationException) {
        throw error
    } catch (error: Exception) {
        failure = error
        context.pause("Recovery deferred: ${error.message.orEmpty().ifBlank { error.javaClass.simpleName }}")
    }
}
