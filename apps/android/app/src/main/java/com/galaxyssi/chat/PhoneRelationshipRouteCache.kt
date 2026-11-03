package com.galaxyssi.chat

/** Reuses verified identity agreements, never the time-dependent MQTT topics or send authorization. */
internal class PhoneRelationshipRouteCache(
    private val capacity: Int = 128,
    private val clock: () -> Long = System::nanoTime
) : RuntimeSensitiveCache {
    private data class Entry(val route: String, val secret: CharArray, val local: String, val remote: String,
        val expiresAt: Long) {
        fun routes() = GalaxySSILinkProtocol.Routes(route, String(secret), local, remote)
        fun wipe() { secret.fill('\u0000') }
    }
    private val entries = LinkedHashMap<String, Entry>(16, 0.75f, true)

    @Synchronized
    fun getOrDerive(local: String, remoteKey: String, expected: String,
        derive: () -> GalaxySSILinkProtocol.Routes?): GalaxySSILinkProtocol.Routes? {
        pruneExpired()
        val key = AgentNativeJsonCodec.sha256(listOf(GalaxySSILinkProtocol.VERSION.toString(), local, remoteKey,
            expected.lowercase(java.util.Locale.ROOT)).joinToString("\u0000"))
        entries[key]?.let { return it.routes() }
        val routes = derive() ?: return null
        check(routes.localFingerprint == local && routes.remoteFingerprint.equals(expected, ignoreCase = true))
        entries[key] = Entry(routes.clientRouteId, routes.linkSecret.toCharArray(), routes.localFingerprint,
            routes.remoteFingerprint, clock() + RuntimeCachePolicy.SENSITIVE_TTL_NANOS)
        while (entries.size > capacity) entries.remove(entries.keys.first())?.wipe()
        RuntimeSensitiveCaches.track(this)
        return routes
    }

    @Synchronized
    override fun pruneExpired(): Boolean {
        val now = clock()
        val iterator = entries.values.iterator()
        while (iterator.hasNext()) {
            val entry = iterator.next()
            if (entry.expiresAt <= now) { iterator.remove(); entry.wipe() }
        }
        return entries.isNotEmpty()
    }

    @Synchronized
    override fun clearSensitive() { entries.values.forEach(Entry::wipe); entries.clear() }

    companion object { val shared = PhoneRelationshipRouteCache() }
}
