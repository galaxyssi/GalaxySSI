package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject

/** Watch outbox adapter for the shared protocol's route revocation hook. */
object GalaxySSILinkDeliveryStore {
    @Volatile private var inboxInstance: GalaxySSILinkInbox? = null
    internal fun transportMetadataDatabase(context: Context) = AndroidPersistentSignalStore.database(context.applicationContext)
    internal fun inbox(context: Context): GalaxySSILinkInbox = inboxInstance ?: synchronized(this) {
        inboxInstance ?: GalaxySSILinkInbox(transportMetadataDatabase(context)).also { inboxInstance = it }
    }
    internal fun peerScope(routes: GalaxySSILinkProtocol.Routes) =
        "${routes.clientRouteId}|${routes.localFingerprint}|${routes.remoteFingerprint}"
    fun discardRoutes(context: Context, routes: GalaxySSILinkProtocol.Routes) {
        val database = AgentEncryptedDatabase(context, "watch_outbox")
        val obsolete = database.entries().filter { (_, value) ->
            runCatching { JSONObject(value).optString("client_route_id") == routes.clientRouteId }
                .getOrDefault(true)
        }.map { it.first }
        database.removeAll(obsolete)
    }
}
