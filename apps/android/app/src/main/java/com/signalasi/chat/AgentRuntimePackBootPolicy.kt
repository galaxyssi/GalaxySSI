package com.signalasi.chat

import android.content.Context
import org.json.JSONObject

/** Persists the last pack set that completed a guest health handshake. */
internal class AgentRuntimePackBootStore(context: Context) {
    private val preferences = context.applicationContext.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

    fun lastHealthyVersions(): Map<String, String> = decode(preferences.getString(KEY_HEALTHY, null))

    fun quarantinedVersions(): Map<String, String> = decode(preferences.getString(KEY_QUARANTINED, null))

    fun recordHealthy(attachments: List<AgentRuntimePackAttachment>) {
        val versions = attachments.associate { it.packId to it.version }.toSortedMap()
        val quarantined = quarantinedVersions().filterNot { (id, version) -> versions[id] == version }
        preferences.edit()
            .putString(KEY_HEALTHY, encode(versions))
            .putString(KEY_QUARANTINED, encode(quarantined))
            .apply()
    }

    fun quarantine(attachments: List<AgentRuntimePackAttachment>) {
        if (attachments.isEmpty()) return
        val updated = quarantinedVersions().toMutableMap()
        attachments.forEach { updated[it.packId] = it.version }
        preferences.edit().putString(KEY_QUARANTINED, encode(updated.toSortedMap())).apply()
    }

    fun isQuarantined(packId: String, version: String): Boolean = quarantinedVersions()[packId] == version

    private fun encode(values: Map<String, String>): String = JSONObject(values).toString()

    private fun decode(raw: String?): Map<String, String> = runCatching {
        val json = JSONObject(raw.orEmpty())
        buildMap {
            json.keys().forEach { id ->
                val version = json.optString(id).trim()
                if (id.isNotBlank() && version.isNotBlank()) put(id, version)
            }
        }.toSortedMap()
    }.getOrDefault(emptyMap())

    companion object {
        private const val PREFERENCES = "signalasi_runtime_pack_boot_v1"
        private const val KEY_HEALTHY = "healthy_versions"
        private const val KEY_QUARANTINED = "quarantined_versions"
    }
}

internal object AgentRuntimePackBootPolicy {
    fun fallbackAttachments(
        desired: List<AgentRuntimePackAttachment>,
        lastHealthyVersions: Map<String, String>
    ): List<AgentRuntimePackAttachment> {
        val knownHealthy = desired.filter { lastHealthyVersions[it.packId] == it.version }
        if (knownHealthy.isNotEmpty() && knownHealthy.size < desired.size) return knownHealthy
        if (desired.isEmpty()) return emptyList()
        val newest = desired.maxByOrNull { it.imageFile.lastModified() } ?: return emptyList()
        return desired.filterNot { it.packId == newest.packId && it.version == newest.version }
    }
}
