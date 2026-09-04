package com.galaxyssi.chat

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
    val capabilities: Set<String>,
    val permissions: List<AgentMarketplacePermission>,
    val permissionDiff: AgentMarketplacePermissionDiff,
    val installedVersion: String,
    val availableVersion: String,
    val updateAvailable: Boolean,
    val rollbackVersions: List<String>,
    val revocable: Boolean,
    val revoked: Boolean,
    val updatedAtMillis: Long
)

object AgentDesktopMarketplaceStore {
    private const val PREFERENCES = "galaxyssi_desktop_marketplace_v1"
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
            val permissionDiff = item.optJSONObject("permission_diff") ?: JSONObject()
            bounded.put(JSONObject()
                .put("id", item.optString("id").take(MAX_TEXT))
                .put("kind", item.optString("kind"))
                .put("name", item.optString("name").take(MAX_TEXT))
                .put("summary", item.optString("summary").take(MAX_TEXT))
                .put("version", item.optString("version").take(80))
                .put("install_state", item.optString("install_state"))
                .put("enabled", item.optBoolean("enabled"))
                .put("trusted", item.optBoolean("trusted", true))
                .put("capabilities", boundedStrings(item.optJSONArray("capabilities"), 96))
                .put("permissions", boundedPermissions(item.optJSONArray("permissions")))
                .put("permission_diff", JSONObject()
                    .put("added", boundedPermissions(permissionDiff.optJSONArray("added")))
                    .put("removed", boundedPermissions(permissionDiff.optJSONArray("removed")))
                    .put("unchanged", boundedPermissions(permissionDiff.optJSONArray("unchanged"))))
                .put("installed_version", item.optString("installed_version").take(80))
                .put("available_version", item.optString("available_version").take(80))
                .put("update_available", item.optBoolean("update_available"))
                .put("rollback_versions", boundedStrings(item.optJSONArray("rollback_versions"), 8))
                .put("revocable", item.optBoolean("revocable"))
                .put("revoked", item.optBoolean("revoked")))
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
        val paired = GalaxySSILinkProtocol.allServerLinks(context)
            .filter { it.paired && GalaxySSICrypto.hasDesktopSession(context, it.desktopId) }
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
                    val permissionDiff = item.optJSONObject("permission_diff") ?: JSONObject()
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
                        capabilities = strings(item.optJSONArray("capabilities")).toSet(),
                        permissions = permissions(item.optJSONArray("permissions")),
                        permissionDiff = AgentMarketplacePermissionDiff(
                            added = permissions(permissionDiff.optJSONArray("added")),
                            removed = permissions(permissionDiff.optJSONArray("removed")),
                            unchanged = permissions(permissionDiff.optJSONArray("unchanged"))
                        ),
                        installedVersion = item.optString("installed_version"),
                        availableVersion = item.optString("available_version").ifBlank {
                            item.optString("version").ifBlank { "1.0.0" }
                        },
                        updateAvailable = item.optBoolean("update_available"),
                        rollbackVersions = strings(item.optJSONArray("rollback_versions")),
                        revocable = item.optBoolean("revocable"),
                        revoked = item.optBoolean("revoked"),
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

    private fun boundedStrings(values: JSONArray?, limit: Int): JSONArray = JSONArray().apply {
        for (index in 0 until minOf(values?.length() ?: 0, limit)) {
            val value = values?.optString(index).orEmpty().trim()
            if (value.isNotBlank()) put(value.take(160))
        }
    }

    private fun boundedPermissions(values: JSONArray?): JSONArray = JSONArray().apply {
        for (index in 0 until minOf(values?.length() ?: 0, 96)) {
            val value = values?.optJSONObject(index) ?: continue
            val id = value.optString("id").trim()
            if (id.isBlank()) continue
            put(JSONObject()
                .put("id", id.take(160))
                .put("title", value.optString("title").ifBlank { id }.take(MAX_TEXT))
                .put("description", value.optString("description").take(MAX_TEXT))
                .put("scope", value.optString("scope", "item").take(80))
                .put("risk", value.optString("risk", "medium").take(40)))
        }
    }

    private fun strings(values: JSONArray?): List<String> = buildList {
        for (index in 0 until (values?.length() ?: 0)) {
            values?.optString(index)?.takeIf(String::isNotBlank)?.let(::add)
        }
    }

    private fun permissions(values: JSONArray?): List<AgentMarketplacePermission> = buildList {
        for (index in 0 until (values?.length() ?: 0)) {
            val value = values?.optJSONObject(index) ?: continue
            val id = value.optString("id")
            if (id.isBlank()) continue
            add(AgentMarketplacePermission(
                id = id,
                title = value.optString("title").ifBlank { id },
                description = value.optString("description"),
                scope = value.optString("scope", "item"),
                risk = value.optString("risk", "medium")
            ))
        }
    }

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
