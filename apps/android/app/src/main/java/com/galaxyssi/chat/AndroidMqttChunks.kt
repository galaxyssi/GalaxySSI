package com.galaxyssi.chat

import android.content.Context
import android.util.Log
import org.json.JSONObject

internal object AndroidMqttChunks {
    @Volatile private var instance: MqttDurableChunks? = null
    private fun store(context: Context) = instance ?: synchronized(this) {
        instance ?: MqttDurableChunks(GalaxySSILinkDeliveryStore.transportMetadataDatabase(context)).also { instance = it }
    }

    private fun scope(routes: GalaxySSILinkProtocol.Routes) = MqttDeliveryEnvelope.receiptBinding(
        GalaxySSILinkDeliveryStore.peerScope(routes), routes.remoteFingerprint.lowercase(), routes.localFingerprint.lowercase(), routes.linkSecret)

    fun accept(context: Context, routes: GalaxySSILinkProtocol.Routes, wire: JSONObject): String? = store(context).accept(scope(routes), wire)

    fun releaseStored(context: Context, routes: GalaxySSILinkProtocol.Routes, transfer: String?, ciphertextDigest: String) {
        if (transfer == null) return
        runCatching {
            val proof = GalaxySSILinkDeliveryStore.inbox(context).replay(GalaxySSILinkDeliveryStore.peerScope(routes), ciphertextDigest) ?: return
            if (proof.wireHash.isNotEmpty()) store(context).releaseAfterStore(scope(routes), transfer, proof.wireHash)
        }.onFailure { Log.w("GalaxySSIRecovery", "Wire fragment cleanup deferred: ${it.javaClass.simpleName}") }
    }
}
