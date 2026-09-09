package com.galaxyssi.chat

/** Independent of the Agent monitor: its owner may be waiting for these workers. */
internal class AgentNativeToolCancellationGroup {
    internal class Invocation {
        val source = AgentNativeToolCancellationSource()
        @Volatile var reason: String = ""
    }

    private val lock = Any()
    private val active = linkedSetOf<Invocation>()

    fun begin(): Invocation = synchronized(lock) {
        Invocation().also(active::add)
    }

    fun end(invocation: Invocation) = synchronized(lock) {
        active.remove(invocation)
    }

    fun cancel(reason: String): Boolean {
        val message = reason.trim().ifBlank { "The native tool stopped reporting progress" }
        val snapshot = synchronized(lock) {
            active.toList().also { invocations -> invocations.forEach { it.reason = message } }
        }
        // Callbacks may finish work or register another invocation; never call them under lock.
        snapshot.forEach { runCatching { it.source.cancel() } }
        return snapshot.isNotEmpty()
    }
}
