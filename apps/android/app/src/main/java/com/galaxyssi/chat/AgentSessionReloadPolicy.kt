package com.galaxyssi.chat

/** A screen refresh may adopt newer durable state, never roll a live task backwards. */
internal object AgentSessionReloadPolicy {
    fun shouldRestore(live: AgentExecutionLoopSnapshot?, saved: AgentExecutionLoopSnapshot?): Boolean = when {
        live == null -> true
        saved == null || saved.taskId != live.taskId -> false
        saved.revision < live.revision -> false
        saved.revision == live.revision -> saved.phase == live.phase && saved.updatedAtMillis >= live.updatedAtMillis
        live.phase.isTerminal -> saved.phase == live.phase
        else -> true
    }
}
