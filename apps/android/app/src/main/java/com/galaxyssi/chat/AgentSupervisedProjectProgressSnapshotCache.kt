package com.galaxyssi.chat

import java.lang.ref.WeakReference

internal data class AgentSupervisedProjectProgressSnapshot(
    val temporarilyBlockedToolIds: Set<String>,
    val detailedToolIds: Set<String>,
    val promptLedger: String?
)

internal object AgentSupervisedProjectProgressSnapshotCache {
    private data class CachedSnapshot(
        val history: WeakReference<List<AgentAction>>,
        val value: AgentSupervisedProjectProgressSnapshot
    )

    private val cacheLock = Any()
    private val snapshots = mutableListOf<CachedSnapshot>()

    fun compile(history: List<AgentAction>): AgentSupervisedProjectProgressSnapshot =
        compile(history) { actions ->
            AgentSupervisedProjectProgressSnapshot(
                temporarilyBlockedToolIds =
                    AgentSupervisedProjectProgressPolicy.temporarilyBlockedToolIds(actions),
                detailedToolIds = AgentSupervisedProjectProgressPolicy.detailedToolIds(actions),
                promptLedger = AgentSupervisedProjectProgressPolicy.promptBlock(actions)
            )
        }

    internal fun compile(
        history: List<AgentAction>,
        compiler: (List<AgentAction>) -> AgentSupervisedProjectProgressSnapshot
    ): AgentSupervisedProjectProgressSnapshot {
        synchronized(cacheLock) {
            takeCached(history)
        }?.let { cached ->
            return cached.value
        }

        val value = compiler(history)
        return synchronized(cacheLock) {
            val cached = takeCached(history)
            if (cached != null) return@synchronized cached.value
            value.also {
                snapshots += CachedSnapshot(WeakReference(history), value)
                while (snapshots.size > MAX_CACHED_SNAPSHOTS) snapshots.removeAt(0)
            }
        }
    }

    private fun takeCached(history: List<AgentAction>): CachedSnapshot? {
        snapshots.removeAll { cached -> cached.history.get() == null }
        val index = snapshots.indexOfFirst { cached -> cached.history.get() === history }
        if (index < 0) return null
        return snapshots.removeAt(index).also(snapshots::add)
    }

    private const val MAX_CACHED_SNAPSHOTS = 8
}
