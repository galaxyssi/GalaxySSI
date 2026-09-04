package com.galaxyssi.chat.voice.asr.remote

import android.content.Context
import com.galaxyssi.chat.AgentEncryptedPreferences
import com.galaxyssi.chat.GalaxySSILinkProtocol
import org.json.JSONObject

object RemoteWhisperNodeRegistry {
    private const val PREFERENCES = "galaxyssi_remote_whisper_nodes"
    private const val KEY_NODES = "nodes"
    private const val MAX_MANIFEST_AGE_MS = 5 * 60 * 1_000L

    @Synchronized
    fun ingest(context: Context, payload: JSONObject, sourceDesktopId: String) {
        if (payload.optString("type") != "capability_manifest") return
        val storage = AgentEncryptedPreferences(context.applicationContext, PREFERENCES)
        val nodes = runCatching { JSONObject(storage.readString(KEY_NODES, "{}")) }
            .getOrDefault(JSONObject())
        val node = RemoteWhisperProtocol.parseCapability(payload, sourceDesktopId)
        if (node == null) {
            if (sourceDesktopId.isNotBlank()) nodes.remove(sourceDesktopId)
        } else {
            nodes.put(node.desktopId, encode(node))
        }
        storage.writeString(KEY_NODES, nodes.toString())
    }

    @Synchronized
    fun best(context: Context, nowMillis: Long = System.currentTimeMillis()): RemoteWhisperNodeCapability? =
        all(context, nowMillis)
            .sortedWith(
                compareByDescending<RemoteWhisperNodeCapability> { it.activeProfile.id == "large-v3-turbo" }
                    .thenByDescending { it.activeProfile.id == "large-v3" }
                    .thenByDescending { it.generatedAtMillis }
            )
            .firstOrNull()

    @Synchronized
    fun all(context: Context, nowMillis: Long = System.currentTimeMillis()): List<RemoteWhisperNodeCapability> {
        val storage = AgentEncryptedPreferences(context.applicationContext, PREFERENCES)
        val nodes = runCatching { JSONObject(storage.readString(KEY_NODES, "{}")) }
            .getOrDefault(JSONObject())
        val valid = mutableListOf<RemoteWhisperNodeCapability>()
        val expired = mutableListOf<String>()
        val keys = nodes.keys()
        while (keys.hasNext()) {
            val desktopId = keys.next()
            val node = decode(nodes.optJSONObject(desktopId))
            val link = GalaxySSILinkProtocol.serverLink(context, desktopId)
            if (node == null || link?.paired != true || link.routes.clientRouteId != node.clientRouteId ||
                nowMillis - node.generatedAtMillis !in 0..MAX_MANIFEST_AGE_MS
            ) {
                expired += desktopId
            } else {
                valid += node
            }
        }
        if (expired.isNotEmpty()) {
            expired.forEach(nodes::remove)
            storage.writeString(KEY_NODES, nodes.toString())
        }
        return valid
    }

    fun clear(context: Context) = AgentEncryptedPreferences(
        context.applicationContext,
        PREFERENCES
    ).clear()

    private fun encode(node: RemoteWhisperNodeCapability): JSONObject = JSONObject()
        .put("desktop_id", node.desktopId)
        .put("desktop_name", node.desktopName)
        .put("client_route_id", node.clientRouteId)
        .put("max_pcm_bytes", node.maxPcmBytes)
        .put("generated_at", node.generatedAtMillis)
        .put("active_profile", JSONObject()
            .put("profile_id", node.activeProfile.id)
            .put("model_name", node.activeProfile.modelName)
            .put("profile_sha256", node.activeProfile.sha256)
            .put("sha_kind", node.activeProfile.shaKind))

    private fun decode(value: JSONObject?): RemoteWhisperNodeCapability? {
        value ?: return null
        return runCatching {
            val profile = value.getJSONObject("active_profile")
            RemoteWhisperNodeCapability(
                desktopId = value.getString("desktop_id"),
                desktopName = value.optString("desktop_name", "GalaxySSI Desktop"),
                clientRouteId = value.getString("client_route_id"),
                activeProfile = RemoteWhisperProfile(
                    id = profile.getString("profile_id"),
                    modelName = profile.optString("model_name", profile.getString("profile_id")),
                    sha256 = profile.getString("profile_sha256"),
                    shaKind = profile.optString("sha_kind", "profile_manifest_sha256")
                ),
                maxPcmBytes = value.getInt("max_pcm_bytes"),
                generatedAtMillis = value.getLong("generated_at")
            )
        }.getOrNull()
    }
}
