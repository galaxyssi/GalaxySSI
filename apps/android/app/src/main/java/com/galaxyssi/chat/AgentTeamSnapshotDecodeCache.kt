package com.galaxyssi.chat

import java.util.Collections
import java.security.MessageDigest

/** The stored ciphertext is checked on every read, including writes made by another store or process. */
internal class AgentTeamSnapshotDecodeCache(
    private val capacity: Int = 128,
    private val maxCharacters: Long = 4_194_304L,
    private val clock: () -> Long = System::nanoTime
) : RuntimeSensitiveCache {
    private data class Entry(val fingerprint: ByteArray, val snapshot: AgentTeamExecutionSnapshot,
        val expiresAt: Long, val characters: Long)
    private val entries = LinkedHashMap<String, Entry>(16, 0.75f, true)
    private var characters = 0L
    private var generation = 0L

    init { require(capacity > 0 && maxCharacters > 0) }

    fun getOrDecode(key: String, ciphertext: String,
        decode: () -> AgentTeamExecutionSnapshot?): AgentTeamExecutionSnapshot? {
        val observedGeneration = synchronized(this) { generation }
        val fingerprint = MessageDigest.getInstance("SHA-256").digest(ciphertext.toByteArray(Charsets.UTF_8))
        synchronized(this) {
            pruneExpired()
            entries[key]?.let { if (it.fingerprint.contentEquals(fingerprint)) return it.snapshot }
            remove(key)
        }
        // Keystore/JSON work must not hold the lock used by UI lifecycle cleanup.
        val value = decode() ?: return null
        val frozen = value.copy(members = Collections.unmodifiableList(value.members.map {
            it.copy(pendingDependencyNames = Collections.unmodifiableList(it.pendingDependencyNames.toList()))
        }))
        val size = frozen.goal.length.toLong() + frozen.finalOutput.length +
            frozen.members.sumOf { it.output.length.toLong() + it.objective.length + it.errorMessage.length +
                it.role.length + it.displayName.length + it.providerLabel.length + it.pendingDependencyNames.sumOf(String::length) }
        if (size > maxCharacters) return frozen
        synchronized(this) {
            if (observedGeneration != generation) return frozen
            pruneExpired()
            remove(key)
            entries[key] = Entry(fingerprint, frozen, clock() + RuntimeCachePolicy.SENSITIVE_TTL_NANOS, size)
            characters += size
            while (entries.size > capacity || characters > maxCharacters) remove(entries.keys.first())
            RuntimeSensitiveCaches.track(this)
        }
        return frozen
    }

    private fun remove(key: String) { characters -= entries.remove(key)?.characters ?: 0L }

    @Synchronized
    override fun pruneExpired(): Boolean {
        val now = clock()
        val iterator = entries.values.iterator()
        while (iterator.hasNext()) {
            val entry = iterator.next()
            if (entry.expiresAt <= now) { characters -= entry.characters; iterator.remove() }
        }
        return entries.isNotEmpty()
    }

    @Synchronized
    override fun clearSensitive() { generation++; entries.clear(); characters = 0L }

    companion object { val shared = AgentTeamSnapshotDecodeCache() }
}
