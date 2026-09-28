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
        AndroidAgentRemoteSilence.start(context)
        AndroidTransportReceipts.connectionChanged(context, connected)
        AndroidAgentResultReceipts.connectionChanged(context, connected)
        coordinator(context).connectionChanged(connected)
    }

    fun request(context: Context) {
        AndroidAgentRemoteSilence.start(context)
        AndroidAgentResultReceipts.request(context)
        coordinator(context).request(GalaxySSIMqttClient.isRequestReplyReady())
    }

    private fun coordinator(context: Context): AgentRecoveryWakeCoordinator = coordinator ?: synchronized(this) {
        coordinator ?: create(context.applicationContext).also { coordinator = it }
    }

    private fun create(context: Context) = AgentRecoveryWakeCoordinator(scope, recover = { retry ->
        recoverPending(context, retry = retry)
    }, failed = { error ->
        Log.w("GalaxySSIRecovery", "Reply recovery wake deferred: ${error.javaClass.simpleName}")
    })

    internal suspend fun recoverPending(context: Context, retry: () -> Unit = {},
        isReady: () -> Boolean = { GalaxySSIMqttClient.isRequestReplyReady() },
        recover: suspend (List<AgentPendingDelivery>, () -> Unit) -> Unit = { deliveries, onRetry ->
            AndroidAgentRemoteRecovery.recoverPendingReplies(context, deliveries, onRetry)
        }) {
        var beforeSource: Long? = null
        while (isReady()) {
            val page = AgentPendingDeliveryStore.page(context, beforeSource)
            val next = page.nextBeforeSource ?: break
            recover(page.deliveries, retry)
            beforeSource = next
            yield()
        }
        if (!isReady()) return
        // Snapshot under the ledger lock; all network work runs outside it. Do not put children in the parent journal.
        val managed = EncryptedAgentManagedResponseLedger(context).pendingRecoveryDeliveries()
            .filter { AgentPendingDeliveryStore.find(context, it.sourceMessageId) == null }
        for (delivery in managed) {
            if (!isReady()) break
            recover(listOf(delivery), retry)
            yield()
        }
    }
}
