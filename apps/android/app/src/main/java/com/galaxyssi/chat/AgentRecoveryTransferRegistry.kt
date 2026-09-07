package com.galaxyssi.chat

/** Coalesces automatic discovery with an existing body transfer, without losing its wake. */
internal class AgentRecoveryTransferRegistry {
    internal class Lease internal constructor(val identity: List<String>, val generation: Long) {
        internal var deferred = false
        internal var finished = false
    }

    private val lock = Any()
    private val active = HashMap<List<String>, Lease>()

    fun begin(identity: List<String>, generation: Long): Lease? = synchronized(lock) {
        require(identity.isNotEmpty() && identity.all { it.isNotBlank() } && generation > 0)
        if ((active[identity]?.generation ?: 0L) >= generation) return@synchronized null
        Lease(identity.toList(), generation).also { active[it.identity] = it }
    }

    fun deferDiscovery(identity: List<String>, isCurrent: (Long) -> Boolean): Boolean {
        val lease = synchronized(lock) { active[identity] } ?: return false
        // Database/fence checks must not hold the registry lock.
        if (!isCurrent(lease.generation)) return false
        return synchronized(lock) {
            if (active[identity] !== lease || lease.finished) false
            else { lease.deferred = true; true }
        }
    }

    /** Returns one deferred wake, also on failure or cancellation before coroutine entry. */
    fun finish(lease: Lease): Boolean = synchronized(lock) {
        if (lease.finished) return@synchronized false
        lease.finished = true
        if (active[lease.identity] === lease) active.remove(lease.identity)
        lease.deferred.also { lease.deferred = false }
    }

    internal val activeCount: Int get() = synchronized(lock) { active.size }
}
