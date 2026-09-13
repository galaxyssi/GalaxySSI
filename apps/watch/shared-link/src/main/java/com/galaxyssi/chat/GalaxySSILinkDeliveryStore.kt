package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject

/** Watch outbox adapter for the shared protocol's route revocation hook. */
object GalaxySSILinkDeliveryStore {
    fun discardRoutes(context: Context, routes: GalaxySSILinkProtocol.Routes) {
        val database = AgentEncryptedDatabase(context, "watch_outbox")
        val obsolete = database.entries().filter { (_, value) ->
            runCatching { JSONObject(value).optString("client_route_id") == routes.clientRouteId }
                .getOrDefault(true)
        }.map { it.first }
        database.removeAll(obsolete)
    }
}
