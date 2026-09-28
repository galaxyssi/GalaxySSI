package com.galaxyssi.chat

import android.content.Context
import android.util.Log
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
                runCatching { sweep(app) }.onFailure {
                    Log.w("GalaxySSIRecovery", "Remote reply watchdog failed", it)
                }
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

    @Synchronized fun terminalObserved(context: Context, source: Long, now: Long = System.currentTimeMillis()) {
        if (source <= 0 || AgentTerminalDeliveryStore.isTerminal(context, source)) return
        val prefs = store(context)
        if (prefs.getLong("$source:terminal", 0) == 0L) {
            prefs.edit().putLong("$source:terminal", now).apply()
        }
    }

    fun terminalDeliveryExpired(context: Context, source: Long, now: Long = System.currentTimeMillis()): Boolean =
        AgentRemoteSilencePolicy.terminalDeliveryExpired(store(context).getLong("$source:terminal", 0), now)

    fun expired(context: Context, source: Long, metadata: Map<String, String>, now: Long = System.currentTimeMillis()): Boolean {
        val prefs = store(context)
        if (terminalDeliveryExpired(context, source, now)) return true
        if (prefs.getLong("$source:terminal", 0) > 0) return false
        val probeAt = prefs.getLong("$source:probe", 0)
        if (probeAt <= 0 || now < probeAt || now - probeAt > 120_000L) return false
        return AgentRemoteSilencePolicy.expired(metadata["resource_started_at"]?.toLongOrNull()?.takeIf { it > 0 }
                ?: prefs.getLong("$source:first", 0),
            maxOf(prefs.getLong("$source:response", 0), metadata["remote_task_status_updated_at"]?.toLongOrNull() ?: 0),
            prefs.getInt("$source:misses", 0), now)
    }

    @Synchronized fun retire(context: Context, source: Long) {
        AndroidAgentRecoveryPacing.retire(context, source)
        store(context).edit().remove("$source:probe").remove("$source:response").remove("$source:misses")
            .remove("$source:first").remove("$source:terminal").apply()
    }

    private suspend fun sweep(context: Context) {
        var cursor: Long? = null
        var needsObservation = false
        val workspaces = EncryptedAgentWorkspaceStore(context)
        do {
            val page = AgentPendingDeliveryStore.page(context, cursor)
            for (delivery in page.deliveries) {
                val workspace = workspaces.find(delivery.turnId) ?: continue
                if (workspace.status.isTerminal || workspace.cancellationRequested ||
                    workspace.conversationId != delivery.conversationId ||
                    AgentPendingDeliveryStore.isSuperseded(context, delivery.sourceMessageId,
                        delivery.conversationId, delivery.turnId)) continue
                if (AgentConnectorResponseStore.hasReceivedDelivery(context, delivery.sourceMessageId,
                        delivery.contactId)) continue
                val session = SharedPreferencesAgentSessionStore(context, "task:${delivery.turnId}").load()
                val metadata = session?.takeIf { it.phase == AgentPhase.WAITING_RESPONSE &&
                    it.lastActionResult?.metadata?.get("source_message_id")?.toLongOrNull() == delivery.sourceMessageId &&
                    it.lastActionResult?.metadata?.get("resource_location") == "desktop" }
                    ?.lastActionResult?.metadata.orEmpty()
                if (expired(context, delivery.sourceMessageId, metadata)) {
                    if (terminalDeliveryExpired(context, delivery.sourceMessageId) || metadata.isEmpty()) {
                        val message = context.getString(if (terminalDeliveryExpired(context, delivery.sourceMessageId))
                            R.string.agent_desktop_result_unavailable else R.string.agent_desktop_status_unavailable)
                        AgentDeliveryFailureRecorder.record(context, delivery.sourceMessageId, delivery.contactId, message)
                    } else {
                        AgentLongTaskRecoveryScheduler.enqueue(context, delivery.turnId,
                            "Desktop task heartbeat recovery exhausted")
                    }
                } else if (GalaxySSIMqttClient.isRequestReplyReady()) {
                    // Invalid/stale bindings cannot be queried, but must not leave the UI spinning forever.
                    if (AndroidAgentRemoteRecovery.hasCurrentBinding(context, delivery)) needsObservation = true
                    else shouldProbe(context, delivery.sourceMessageId)
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
