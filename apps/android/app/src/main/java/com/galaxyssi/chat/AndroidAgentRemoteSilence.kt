package com.galaxyssi.chat

import android.content.Context
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/** Task-level liveness, not MQTT socket health. Only authenticated observations renew the lease. */
internal object AndroidAgentRemoteSilence {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var started = false
    private fun store(context: Context) = context.getSharedPreferences("agent_remote_silence_v1", Context.MODE_PRIVATE)

    @Synchronized fun start(context: Context) {
        if (started) return
        started = true
        val app = context.applicationContext
        scope.launch {
            while (isActive) {
                runCatching { sweep(app) }
                delay(AgentRemoteSilencePolicy.PROBE_INTERVAL)
            }
        }
    }

    @Synchronized fun shouldProbe(context: Context, source: Long, now: Long = System.currentTimeMillis()): Boolean {
        val prefs = store(context)
        val previous = prefs.getLong("$source:probe", 0)
        if (previous > 0 && now >= previous && now - previous < AgentRemoteSilencePolicy.PROBE_INTERVAL) return false
        val misses = if (previous <= 0 || now < previous || now - previous > 120_000L) 0
            else prefs.getInt("$source:misses", 0)
        prefs.edit().putLong("$source:probe", now)
            .putLong("$source:first", prefs.getLong("$source:first", now))
            .putInt("$source:misses", (misses + 1).coerceAtMost(100)).apply()
        return true
    }

    @Synchronized fun observed(context: Context, source: Long, now: Long = System.currentTimeMillis()) {
        if (source <= 0 || AgentTerminalDeliveryStore.isTerminal(context, source)) return
        store(context).edit().putLong("$source:response", now).putInt("$source:misses", 0).apply()
    }

    fun expired(context: Context, source: Long, metadata: Map<String, String>, now: Long = System.currentTimeMillis()): Boolean {
        val prefs = store(context)
        val probeAt = prefs.getLong("$source:probe", 0)
        if (probeAt <= 0 || now < probeAt || now - probeAt > 120_000L) return false
        return AgentRemoteSilencePolicy.expired(metadata["resource_started_at"]?.toLongOrNull()?.takeIf { it > 0 }
                ?: prefs.getLong("$source:first", 0),
            maxOf(prefs.getLong("$source:response", 0), metadata["remote_task_status_updated_at"]?.toLongOrNull() ?: 0),
            prefs.getInt("$source:misses", 0), now)
    }

    @Synchronized fun retire(context: Context, source: Long) {
        store(context).edit().remove("$source:probe").remove("$source:response").remove("$source:misses")
            .remove("$source:first").apply()
    }

    private suspend fun sweep(context: Context) {
        var cursor: Long? = null
        var needsObservation = false
        do {
            val page = AgentPendingDeliveryStore.page(context, cursor)
            for (delivery in page.deliveries) {
                val session = SharedPreferencesAgentSessionStore(context, "task:${delivery.turnId}").load() ?: continue
                if (session.phase != AgentPhase.WAITING_RESPONSE ||
                    session.lastActionResult?.metadata?.get("source_message_id")?.toLongOrNull() != delivery.sourceMessageId) continue
                val metadata = session.lastActionResult.metadata
                if (metadata["resource_location"] != "desktop") continue
                if (expired(context, delivery.sourceMessageId, metadata)) {
                    AgentLongTaskRecoveryScheduler.enqueue(context, delivery.turnId, "Desktop task heartbeat recovery exhausted")
                } else if (GalaxySSIMqttClient.isRequestReplyReady()) {
                    // The recovery owner sends independent requests; the watchdog never blocks on network IO.
                    needsObservation = true
                } else {
                    // Offline probes consume no network and create no durable MQTT records.
                    shouldProbe(context, delivery.sourceMessageId)
                }
            }
            cursor = page.nextBeforeSource
        } while (cursor != null)
        if (needsObservation) AndroidAgentRecoveryWake.request(context)
    }
}
