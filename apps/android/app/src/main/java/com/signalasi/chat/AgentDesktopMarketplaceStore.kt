package com.signalasi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

data class AgentDesktopMarketplaceItem(
    val desktopId: String,
    val desktopName: String,
    val id: String,
    val kind: AgentCapabilityCatalogKind,
    val name: String,
    val summary: String,
    val version: String,
    val installState: AgentMarketplaceInstallState,
    val enabled: Boolean,
    val trusted: Boolean,
    val updatedAtMillis: Long
)

object AgentDesktopMarketplaceStore {
    private const val PREFERENCES = "signalasi_desktop_marketplace_v1"
    private const val MANIFESTS = "manifests"
    private const val MAX_ITEMS_PER_DESKTOP = 512
    private const val MAX_TEXT = 500

    fun update(context: Context, payload: JSONObject) {
        if (payload.optString("type") != "capability_manifest") return
        val server = payload.optJSONObject("server") ?: return
        val desktopId = server.optString("id").trim()
        val marketplace = payload.optJSONObject("tool_marketplace") ?: return
        val items = marketplace.optJSONArray("items") ?: return
        if (desktopId.isBlank()) return
        val bounded = JSONArray()
        for (index in 0 until minOf(items.length(), MAX_ITEMS_PER_DESKTOP)) {
            val item = items.optJSONObject(index) ?: continue
            if (kind(item.optString("kind")) == null || state(item.optString("install_state")) == null) continue
            bounded.put(JSONObject()
                .put("id", item.optString("id").take(MAX_TEXT))
                .put("kind", item.optString("kind"))
                .put("name", item.optString("name").take(MAX_TEXT))
                .put("summary", item.optString("summary").take(MAX_TEXT))
                .put("version", item.optString("version").take(80))
                .put("install_state", item.optString("install_state"))
                .put("enabled", item.optBoolean("enabled"))
                .put("trusted", item.optBoolean("trusted", true)))
        }
        val root = read(context)
        root.put(desktopId, JSONObject()
            .put("desktop_id", desktopId)
            .put("desktop_name", server.optString("name").take(160))
            .put("updated_at", System.currentTimeMillis())
            .put("items", bounded))
        write(context, root)
    }

    fun remove(context: Context, desktopId: String) {
        val root = read(context)
        root.remove(desktopId)
        write(context, root)
    }

    fun list(
        context: Context,
        selectedKind: AgentCapabilityCatalogKind? = null
    ): List<AgentDesktopMarketplaceItem> {
        val paired = SignalASILinkProtocol.allServerLinks(context)
            .filter { it.paired && SignalASICrypto.hasDesktopSession(context, it.desktopId) }
            .mapTo(linkedSetOf()) { it.desktopId }
        val root = read(context)
        return buildList {
            root.keys().forEach { desktopId ->
                if (desktopId !in paired) return@forEach
                val manifest = root.optJSONObject(desktopId) ?: return@forEach
                val items = manifest.optJSONArray("items") ?: return@forEach
                for (index in 0 until items.length()) {
                    val item = items.optJSONObject(index) ?: continue
                    val itemKind = kind(item.optString("kind")) ?: continue
                    val installState = state(item.optString("install_state")) ?: continue
                    if (selectedKind != null && selectedKind != itemKind) continue
                    add(AgentDesktopMarketplaceItem(
                        desktopId = desktopId,
                        desktopName = manifest.optString("desktop_name").ifBlank { desktopId },
                        id = item.optString("id"),
                        kind = itemKind,
                        name = item.optString("name"),
                        summary = item.optString("summary"),
                        version = item.optString("version").ifBlank { "1.0.0" },
                        installState = installState,
                        enabled = item.optBoolean("enabled"),
                        trusted = item.optBoolean("trusted", true),
                        updatedAtMillis = manifest.optLong("updated_at")
                    ))
                }
            }
        }.sortedWith(compareBy({ it.desktopName.lowercase() }, { it.name.lowercase() }))
    }

    private fun kind(value: String): AgentCapabilityCatalogKind? =
        AgentCapabilityCatalogKind.entries.firstOrNull { it.wireValue == value }

    private fun state(value: String): AgentMarketplaceInstallState? =
        AgentMarketplaceInstallState.entries.firstOrNull { it.wireValue == value }

    private fun read(context: Context): JSONObject {
        val raw = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .getString(MANIFESTS, "{}").orEmpty()
        return runCatching { JSONObject(raw) }.getOrDefault(JSONObject())
    }

    private fun write(context: Context, value: JSONObject) {
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putString(MANIFESTS, value.toString())
            .apply()
    }
}
