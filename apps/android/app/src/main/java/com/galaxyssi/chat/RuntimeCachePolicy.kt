package com.galaxyssi.chat

import java.util.WeakHashMap
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

internal object RuntimeCachePolicy {
    const val SENSITIVE_TTL_MILLIS = 600_000L
    const val SENSITIVE_TTL_NANOS = SENSITIVE_TTL_MILLIS * 1_000_000L
    const val STATIC_METADATA_TTL_NANOS = 24L * 60 * 60 * 1_000_000_000L
}

internal interface RuntimeSensitiveCache {
    /** Drops expired references and returns whether any cached values remain. */
    fun pruneExpired(): Boolean
    fun clearSensitive()
}

/** One idle-stopping sweeper; registrations must not keep cache owners alive. */
internal object RuntimeSensitiveCaches {
    private val lock = Any()
    private val caches = WeakHashMap<RuntimeSensitiveCache, Unit>()
    private val executor = Executors.newSingleThreadScheduledExecutor { task ->
        Thread(task, "galaxyssi-cache-expiry").apply { isDaemon = true }
    }
    private var sweep: ScheduledFuture<*>? = null
    private var revision = 0L

    fun track(cache: RuntimeSensitiveCache) = synchronized(lock) {
        caches[cache] = Unit
        revision++
        if (sweep == null) {
            sweep = executor.scheduleWithFixedDelay(::pruneExpired, 1, 1, TimeUnit.SECONDS)
        }
    }

    fun pruneExpired() {
        val (observedRevision, targets) = synchronized(lock) { revision to caches.keys.toList() }
        var active = false
        targets.forEach { cache ->
            active = runCatching { cache.pruneExpired() }.getOrDefault(true) || active
        }
        synchronized(lock) {
            if (!active && revision == observedRevision) {
                sweep?.cancel(false)
                sweep = null
            }
        }
    }

    fun clearAll() {
        val targets = synchronized(lock) { caches.keys.toList() }
        targets.forEach(RuntimeSensitiveCache::clearSensitive)
    }
}
