package com.galaxyssi.chat

/** Only reuse plaintext after the caller has read the current authenticated row envelope. */
internal class AgentEncryptedRowCache(
    private val capacity: Int = 256,
    private val maxCharacters: Int = 2 * 1024 * 1024,
    private val maxEntryCharacters: Int = 256 * 1024,
    private val ttlNanos: Long = minOf(30_000_000_000L, RuntimeCachePolicy.SENSITIVE_TTL_NANOS),
    private val clockNanos: () -> Long = System::nanoTime
) : RuntimeSensitiveCache {
    private data class RowKey(val storageIdentity: String, val key: String)
    private data class Value(val encrypted: String, val plaintext: CharArray, val expiresAt: Long) {
        val characters: Int get() = encrypted.length + plaintext.size
        fun wipe() = plaintext.fill('\u0000')
    }

    private val values = LinkedHashMap<RowKey, Value>(16, 0.75f, true)
    private var characters = 0
    private var revision = 0L

    init {
        require(capacity > 0 && maxCharacters > 0 && maxEntryCharacters > 0 && ttlNanos > 0)
        // Register before a potentially slow decrypt so a concurrent lifecycle wipe fences its result.
        RuntimeSensitiveCaches.track(this)
    }

    fun read(storageIdentity: String, key: String, encrypted: String, decrypt: () -> String?): String? {
        val row = RowKey(storageIdentity, key)
        val observedRevision = synchronized(this) {
            val cached = values[row]
            if (cached != null) {
                if (cached.encrypted == encrypted && cached.expiresAt > clockNanos()) {
                    return String(cached.plaintext)
                }
                remove(row)
            }
            revision
        }
        val plaintext = decrypt() ?: return null
        publish(storageIdentity, key, encrypted, plaintext, observedRevision)
        return plaintext
    }

    /** Call before mutation; publish only after the outermost database transaction commits. */
    @Synchronized
    fun invalidate(storageIdentity: String, keys: Collection<String>): Long {
        revision++
        keys.forEach { remove(RowKey(storageIdentity, it)) }
        return revision
    }

    @Synchronized
    fun publish(storageIdentity: String, key: String, encrypted: String, plaintext: String, observedRevision: Long) {
        if (revision != observedRevision) return
        prune(clockNanos())
        val row = RowKey(storageIdentity, key)
        remove(row)
        val size = encrypted.length.toLong() + plaintext.length
        if (size > maxEntryCharacters || size > maxCharacters) return
        while (values.size >= capacity || characters.toLong() + size > maxCharacters) {
            remove(values.keys.first())
        }
        values[row] = Value(encrypted, plaintext.toCharArray(), clockNanos() + ttlNanos)
        characters += size.toInt()
        RuntimeSensitiveCaches.track(this)
    }

    @Synchronized
    fun clearStorage(storageIdentity: String) {
        revision++
        values.keys.filter { it.storageIdentity == storageIdentity }.forEach(::remove)
    }

    @Synchronized
    override fun clearSensitive() {
        revision++
        values.values.forEach(Value::wipe)
        values.clear()
        characters = 0
    }

    @Synchronized
    override fun pruneExpired(): Boolean {
        prune(clockNanos())
        return values.isNotEmpty()
    }

    private fun prune(now: Long) {
        values.filterValues { it.expiresAt <= now }.keys.forEach(::remove)
    }

    private fun remove(row: RowKey) {
        values.remove(row)?.let { value ->
            characters -= value.characters
            value.wipe()
        }
    }

    companion object {
        val shared = AgentEncryptedRowCache()
    }
}
