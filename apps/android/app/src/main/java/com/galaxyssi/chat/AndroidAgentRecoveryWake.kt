package com.galaxyssi.chat

import android.content.Context
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.yield

/** Read-only reply recovery is independent of foreground task/maintenance scheduling. */
internal object AndroidAgentRecoveryWake {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    @Volatile private var coordinator: AgentRecoveryWakeCoordinator? = null

    fun connectionChanged(context: Context, connected: Boolean) {
        coordinator(context).connectionChanged(connected)
    }

    fun request(context: Context) {
        coordinator(context).request(GalaxySSIMqttClient.isConnected())
    }

    private fun coordinator(context: Context): AgentRecoveryWakeCoordinator = coordinator ?: synchronized(this) {
        coordinator ?: create(context.applicationContext).also { coordinator = it }
    }

    private fun create(context: Context) = AgentRecoveryWakeCoordinator(scope, recover = {
        // Legacy preferences require a key snapshot, but bodies are decrypted only one page at a time.
        val sources = AgentPendingDeliveryStore.sourceIds(context)
        var offset = 0
        while (offset < sources.size && GalaxySSIMqttClient.isConnected()) {
            val end = minOf(offset + 32, sources.size)
            val page = (offset until end).mapNotNull { index ->
                AgentPendingDeliveryStore.find(context, sources[index])
            }
            AndroidAgentRemoteRecovery.recoverPendingReplies(context, page)
            offset = end
            yield()
        }
    }, failed = { error ->
        Log.w("GalaxySSIRecovery", "Reply recovery wake deferred: ${error.javaClass.simpleName}")
    })
}
