package com.galaxyssi.chat

import android.content.Context
import java.util.concurrent.ConcurrentHashMap

/** Row-level checkpoints; legacy encrypted roots remain readable without a startup-wide migration. */
internal class AgentSessionRootStorage(
    context: Context,
    legacyName: String = SharedPreferencesAgentSessionStore.PREFS,
    databaseName: String = DATABASE_NAME
) {
    private val legacy = AgentEncryptedPreferences(context, legacyName)
    private val rows = AgentEncryptedDatabase(context, databaseName)
    private val lock = locks.computeIfAbsent(context.getDatabasePath(databaseName).absolutePath) { Any() }

    fun readString(key: String, defaultValue: String): String = synchronized(lock) {
        when {
            rows.contains(removedKey(key)) -> defaultValue
            rows.contains(key) -> rows.readString(key, defaultValue)
            else -> legacy.readString(key, defaultValue)
        }
    }

    fun encodedValueLength(key: String): Int = synchronized(lock) {
        when {
            rows.contains(removedKey(key)) -> 0
            rows.contains(key) -> rows.encodedValueLength(key)
            else -> legacy.encodedValueLength(key)
        }
    }

    fun writeString(key: String, value: String) = synchronized(lock) {
        rows.mutateStrings(mapOf(key to value), listOf(removedKey(key)))
    }

    fun remove(key: String) = synchronized(lock) {
        // Persist the tombstone with removal: a crash must not resurrect the legacy root.
        rows.mutateStrings(mapOf(removedKey(key) to "1"), listOf(key))
    }

    fun removeDurably(key: String) = remove(key)

    fun keys(): Set<String> = synchronized(lock) {
        val stored = rows.keys()
        val removed = stored.filter { it.startsWith(REMOVED_PREFIX) }.map { it.removePrefix(REMOVED_PREFIX) }.toSet()
        (legacy.keys() + stored.filterNot { it.startsWith(REMOVED_PREFIX) }) - removed
    }

    private fun removedKey(key: String) = "$REMOVED_PREFIX$key"

    companion object {
        const val DATABASE_NAME = "galaxyssi_agent_runtime_rows_v1"
        private const val REMOVED_PREFIX = "checkpoint-removed:"
        private val locks = ConcurrentHashMap<String, Any>()
    }
}
