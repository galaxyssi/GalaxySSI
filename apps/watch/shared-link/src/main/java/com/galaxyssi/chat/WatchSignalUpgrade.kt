package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject

/** Preserve the first watch build's identity when adopting Android's transactional Signal store. */
object WatchSignalUpgrade {
    fun prepare(context: Context) {
        val database = AndroidPersistentSignalStore.database(context)
        database.indexedTransaction {
            if (database.contains("identity_key_pair")) return@indexedTransaction
            val legacy = AgentEncryptedPreferences(context, "galaxyssi_signal_store")
            if (!legacy.contains("identity_key_pair")) return@indexedTransaction
            val state = JSONObject()
            legacy.keys().forEach { key ->
                val value = legacy.readString(key, "")
                check(value.isNotBlank()) { "Legacy watch Signal record is unreadable" }
                state.put(key, value)
            }
            AndroidPersistentSignalStore.importJson(context, state)
            // Validate before committing, so failure cannot replace the old identity.
            AndroidPersistentSignalStore(context)
        }
        // Keep the encrypted legacy store intact; upgrades never destroy the fallback.
    }
}
