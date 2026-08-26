package com.signalasi.chat

import android.content.Context
import org.json.JSONArray

internal object ContactConversationPreferences {
    private const val PREFS = "contact_conversation_preferences"
    private const val KEY_PINNED_CONTACT_IDS = "pinned_contact_ids"
    private val lock = Any()

    fun isPinned(context: Context, contactId: String): Boolean =
        contactId.isNotBlank() && synchronized(lock) {
            contactId in pinnedIds(context)
        }

    fun setPinned(context: Context, contactId: String, pinned: Boolean): Boolean {
        if (contactId.isBlank()) return false
        synchronized(lock) {
            val ids = pinnedIds(context).toMutableSet()
            val changed = if (pinned) ids.add(contactId) else ids.remove(contactId)
            if (changed) writePinnedIds(context, ids)
            return changed
        }
    }

    fun remove(context: Context, contactId: String) {
        setPinned(context, contactId, false)
    }

    private fun pinnedIds(context: Context): Set<String> {
        val raw = storage(context).readString(KEY_PINNED_CONTACT_IDS, "[]")
        val array = runCatching { JSONArray(raw) }.getOrDefault(JSONArray())
        return buildSet {
            for (index in 0 until array.length()) {
                array.optString(index).trim().takeIf(String::isNotBlank)?.let(::add)
            }
        }
    }

    private fun writePinnedIds(context: Context, ids: Set<String>) {
        storage(context).writeString(
            KEY_PINNED_CONTACT_IDS,
            JSONArray(ids.sorted()).toString()
        )
    }

    private fun storage(context: Context): AgentEncryptedPreferences =
        AgentEncryptedPreferences(context.applicationContext, PREFS)
}
