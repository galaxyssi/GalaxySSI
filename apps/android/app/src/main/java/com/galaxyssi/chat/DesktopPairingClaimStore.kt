package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject

internal object DesktopPairingClaimStore {
    private fun storage(context: Context) =
        AgentEncryptedPreferences(context.applicationContext, "desktop_pairing_claim_v1")

    @Synchronized
    fun save(context: Context, desktopId: String, topic: String, wire: String, createdAt: Long) {
        storage(context).writeString("pending", JSONObject()
            .put("desktop_id", desktopId).put("topic", topic).put("wire", wire)
            .put("created_at", createdAt).put("local_identity", GalaxySSICrypto.localIdentitySha256()).toString())
    }

    @Synchronized
    fun restore(context: Context): JSONObject? {
        val value = JSONObject(storage(context).readString("pending", "{}"))
        if (value.optString("desktop_id").isBlank()) return null
        if (value.optString("local_identity") != GalaxySSICrypto.localIdentitySha256() ||
            GalaxySSILinkProtocol.serverLink(context, value.optString("desktop_id"))?.paired != false
        ) {
            storage(context).removeDurably("pending")
            return null
        }
        return value
    }

    @Synchronized
    fun clear(context: Context, desktopId: String) {
        val value = JSONObject(storage(context).readString("pending", "{}"))
        if (value.optString("desktop_id") == desktopId) storage(context).removeDurably("pending")
    }
}
