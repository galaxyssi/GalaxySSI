package com.galaxyssi.chat

import java.util.Collections

/** Stores only model catalog fields, never contacts, credentials, routes or availability. */
internal class AgentInvocationMetadataCache(
    private val clockNanos: () -> Long = System::nanoTime,
    private val capacity: Int = 64
) {
    private data class Entry(val profile: AgentInvocationProfile, val expiresAt: Long)
    private val entries = LinkedHashMap<String, Entry>(16, 0.75f, true)
    private var version = ""

    init { require(capacity > 0) }

    @Synchronized
    fun get(fingerprint: String, appVersion: String, decode: () -> AgentInvocationProfile): AgentInvocationProfile {
        if (version != appVersion) {
            entries.clear()
            version = appVersion
        }
        val now = clockNanos()
        entries.entries.removeAll { it.value.expiresAt <= now }
        entries[fingerprint]?.let { return it.profile }
        val profile = decode().let {
            it.copy(models = Collections.unmodifiableList(it.models.toList()),
                reasoningEfforts = Collections.unmodifiableList(it.reasoningEfforts.toList()))
        }
        val characters = profile.models.sumOf {
            it.id.length.toLong() + it.displayName.length + it.description.length
        }
        if (profile.models.size > 128 || characters > 65_536L) return profile
        entries[fingerprint] = Entry(profile, now + RuntimeCachePolicy.STATIC_METADATA_TTL_NANOS)
        while (entries.size > capacity) entries.remove(entries.keys.first())
        return profile
    }

    @Synchronized
    fun invalidate() { entries.clear() }

    companion object {
        val shared = AgentInvocationMetadataCache()
    }
}
