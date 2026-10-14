package com.galaxyssi.chat

internal data class GlobalResearchClaimSelection(
    val tasks: List<GlobalResearchTask>,
    val claimed: GlobalResearchTask?
)

/** Process-local ownership covers preparation only; dispatched work keeps its durable lease. */
internal object GlobalResearchClaimCoordinator {
    private val preparations = mutableMapOf<Pair<String, String>, Long>()

    @Synchronized
    fun claim(original: List<GlobalResearchTask>, now: Long, attentionOnly: Boolean,
        storeKey: String): GlobalResearchClaimSelection {
        val tasks = original.map { originalTask ->
            val task = GlobalResearchTaskPolicy.recoverIfStale(originalTask, now)
            val abandoned = ProactiveAttentionPolicy.isAttention(task) &&
                task.status == GlobalResearchTaskStatus.RUNNING &&
                (storeKey to task.id) !in preparations && task.sourceMessageId == 0L &&
                task.researchPlan.runningUnits().isEmpty() && task.researchPlan.synthesisSourceMessageId == 0L
            if (abandoned) task.copy(status = GlobalResearchTaskStatus.WAITING_FOR_RESOURCE,
                nextAttemptAtMillis = now, leaseExpiresAtMillis = 0L,
                attemptCount = (task.attemptCount - 1).coerceAtLeast(0), updatedAtMillis = now) else task
        }.toMutableList()
        val attentionRunning = tasks.any { ProactiveAttentionPolicy.isAttention(it) &&
            it.status == GlobalResearchTaskStatus.RUNNING }
        val index = tasks.indices.filter { index ->
            val task = tasks[index]
            (!attentionOnly || ProactiveAttentionPolicy.isAttention(task)) &&
                (!ProactiveAttentionPolicy.isAttention(task) || !attentionRunning) &&
                task.status in setOf(GlobalResearchTaskStatus.QUEUED, GlobalResearchTaskStatus.SCHEDULED,
                    GlobalResearchTaskStatus.WAITING_FOR_RESOURCE) && task.nextAttemptAtMillis <= now
        }.maxWithOrNull(compareBy<Int> { ProactiveAttentionNewsPolicy.priority(tasks[it]) }
            .thenBy { GlobalResearchTaskPolicy.selectionScore(tasks[it], now) })
            ?: return GlobalResearchClaimSelection(tasks, null)
        val claimed = tasks[index].copy(status = GlobalResearchTaskStatus.RUNNING,
            attemptCount = tasks[index].attemptCount + 1, sourceMessageId = 0L,
            leaseExpiresAtMillis = now + GlobalResearchTaskPolicy.leaseMillis(tasks[index].depth),
            updatedAtMillis = now)
        tasks[index] = claimed
        if (ProactiveAttentionPolicy.isAttention(claimed)) preparations[storeKey to claimed.id] = now
        return GlobalResearchClaimSelection(tasks, claimed)
    }

    @Synchronized
    fun release(storeKey: String, task: GlobalResearchTask) {
        val key = storeKey to task.id
        if (preparations[key] == task.updatedAtMillis) preparations.remove(key)
    }

    fun attentionNextWake(tasks: List<GlobalResearchTask>): Long? {
        val attention = tasks.filter(ProactiveAttentionPolicy::isAttention)
        val running = attention.filter { it.status == GlobalResearchTaskStatus.RUNNING }
        if (running.isNotEmpty()) return running.minOf { it.leaseExpiresAtMillis.coerceAtLeast(0L) + 1L }
        return attention.filter { it.status in setOf(GlobalResearchTaskStatus.QUEUED,
            GlobalResearchTaskStatus.WAITING_FOR_RESOURCE, GlobalResearchTaskStatus.SCHEDULED) }
            .minOfOrNull { it.nextAttemptAtMillis }
    }
}
