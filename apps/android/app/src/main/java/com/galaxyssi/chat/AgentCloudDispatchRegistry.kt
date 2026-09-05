package com.galaxyssi.chat

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

internal data class AgentCloudDispatchIdentity(
    val sourceMessageId: Long,
    val contactId: String,
    val conversationId: String,
    val turnId: String,
    val taskId: String,
    val actionId: String
) {
    companion object {
        fun from(result: AgentActionResult): AgentCloudDispatchIdentity? {
            val metadata = result.metadata
            if (metadata["resource_location"] != "cloud") return null
            return AgentCloudDispatchIdentity(
                metadata["source_message_id"]?.toLongOrNull()?.takeIf { it > 0 } ?: return null,
                metadata["contact_id"].orEmpty(), metadata["conversation_id"].orEmpty(),
                metadata["turn_id"].orEmpty(), metadata["task_id"].orEmpty(), result.actionId)
        }
    }
}

/** One terminal decision per dispatch; no lock is shared by different conversations. */
internal class AgentCloudDispatchLease {
    private enum class State { ACTIVE, COMPLETED, CANCELLED }
    private val state = AtomicReference(State.ACTIVE)
    private val cancelled = CountDownLatch(1)
    private val cancellation = AgentNativeToolCancellationSource()

    val isCancelled: Boolean get() = state.get() == State.CANCELLED

    fun cancel(): Boolean {
        if (!state.compareAndSet(State.ACTIVE, State.CANCELLED)) return false
        cancelled.countDown()
        cancellation.cancel()
        return true
    }

    fun bind(job: Job): AgentNativeToolCancellationRegistration =
        cancellation.token.invokeOnCancellation { job.cancel(CancellationException("Cloud dispatch cancelled")) }

    fun <T> runRequest(block: suspend () -> T): T = kotlinx.coroutines.runBlocking {
        val registration = bind(requireNotNull(coroutineContext[Job]))
        try { checkActive(); block() } finally { registration.dispose() }
    }

    fun claimCompletion(): Boolean = state.compareAndSet(State.ACTIVE, State.COMPLETED)

    fun awaitRetry(delayMillis: Long): Boolean = !cancelled.await(delayMillis, TimeUnit.MILLISECONDS)

    fun checkActive() {
        if (isCancelled) throw CancellationException("Cloud dispatch cancelled")
    }
}

internal object AgentCloudDispatchRegistry {
    private val active = ConcurrentHashMap<AgentCloudDispatchIdentity, AgentCloudDispatchLease>()

    fun register(identity: AgentCloudDispatchIdentity): AgentCloudDispatchLease {
        val lease = AgentCloudDispatchLease()
        check(active.putIfAbsent(identity, lease) == null) { "Cloud dispatch is already active" }
        return lease
    }

    fun cancel(result: AgentActionResult?): Boolean = result?.let(AgentCloudDispatchIdentity::from)
        ?.let { active[it]?.cancel() } ?: false

    fun release(identity: AgentCloudDispatchIdentity, lease: AgentCloudDispatchLease) {
        active.remove(identity, lease)
    }

    internal fun activeCount() = active.size
}
