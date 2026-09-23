package com.galaxyssi.watch

/** Mirrors Android's five-minute / three-probe remote silence lease. */
internal class WatchRemoteSilence {
    private data class Probe(var anchor: Long, var lastAt: Long = 0, var misses: Int = 0)
    private val probes = mutableMapOf<String, Probe>()

    fun expired(task: WatchTask, now: Long): Boolean {
        if (task.state.terminal || task.desktopId in setOf("api", "watch-location") || task.localOperation.isNotEmpty()) {
            probes.remove(task.id)
            return false
        }
        val anchor = maxOf(task.sourceId, task.remoteObservedAt)
        if (anchor <= 0 || now < anchor) return false
        val probe = probes.getOrPut(task.id) { Probe(anchor) }
        if (probe.anchor != anchor) {
            probe.anchor = anchor
            probe.lastAt = 0
            probe.misses = 0
        }
        if (probe.lastAt == 0L || now < probe.lastAt || now - probe.lastAt >= PROBE_INTERVAL) {
            probe.lastAt = now
            probe.misses = (probe.misses + 1).coerceAtMost(100)
        }
        return now - anchor >= SILENCE_LIMIT && probe.misses >= MIN_PROBES
    }

    companion object {
        const val PROBE_INTERVAL = 30_000L
        const val SILENCE_LIMIT = 5 * 60_000L
        const val MIN_PROBES = 3
    }
}
