package com.galaxyssi.chat

import android.content.Context

/** Build subscription and authentication indexes from the same relationship snapshot. */
internal object AndroidMqttPeerBindings {
    data class Snapshot(
        val desktops: List<GalaxySSILinkProtocol.ServerLink>,
        val phones: List<Pair<String, GalaxySSILinkProtocol.Routes>>,
        val bindings: List<MqttPeerRoutes.Binding>
    )

    fun load(context: Context): Snapshot {
        val desktops = GalaxySSILinkProtocol.allServerLinks(context)
        // Match phoneRoutesForIdentity: a current contact wins over its older pairing request.
        val phones = AppStore.phoneTransportBindings(context).distinctBy { it.first }
        val bindings = desktops.map { binding(it.routes, it.paired) } + phones.map {
            binding(it.second, AppStore.canCommunicateWith(context, it.first))
        }
        return Snapshot(desktops, phones, bindings.distinct())
    }

    private fun binding(routes: GalaxySSILinkProtocol.Routes, enabled: Boolean) = MqttPeerRoutes.Binding(
        scope = GalaxySSILinkDeliveryStore.peerScope(routes),
        sender = routes.localFingerprint.lowercase(),
        receiver = routes.remoteFingerprint.lowercase(),
        secret = routes.linkSecret,
        sendTopic = routes.up,
        sendTopics = routes.sendWindow,
        receiveTopics = routes.receiveWindow,
        enabled = enabled
    )
}
