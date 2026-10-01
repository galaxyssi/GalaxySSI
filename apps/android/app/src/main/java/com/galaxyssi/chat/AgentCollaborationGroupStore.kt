package com.galaxyssi.chat

import android.content.Context
import java.util.concurrent.ConcurrentHashMap

internal class CollaborationGroupStore(context: Context) {
    private val appContext = context.applicationContext
    private val database = AgentEncryptedDatabase(context.applicationContext, "galaxyssi_collaboration_groups_v1")

    fun load(conversationId: String): CollaborationGroup? = synchronized(LOCK) {
        if (conversationId in loaded) return@synchronized cache[conversationId]
        val raw = database.readString(conversationId, "")
        val group = if (raw.isBlank()) null else requireNotNull(CollaborationGroupCodec.decode(raw)) {
            "Invalid collaboration group; refusing to silently use a different Agent"
        }
        group?.let { cache[conversationId] = it }
        loaded.add(conversationId)
        group
    }

    fun update(conversationId: String, transform: (CollaborationGroup) -> CollaborationGroup): CollaborationGroup =
        synchronized(LOCK) {
            val before = load(conversationId) ?: CollaborationGroup(conversationId)
            val after = transform(before).copy(revision = before.revision + 1).validate()
            require(after.conversationId == conversationId)
            database.writeString(conversationId, CollaborationGroupCodec.encode(after))
            cache[conversationId] = after
            loaded.add(conversationId)
            AgentConversationWindows.changed()
            after
        }

    fun remove(conversationId: String) {
        synchronized(LOCK) {
            database.remove(conversationId)
            cache.remove(conversationId)
            loaded.remove(conversationId)
        }
        CollaborationResearchArchive.remove(appContext, conversationId)
    }

    fun clear() {
        val ids = synchronized(LOCK) {
            val ids = database.keys("")
            database.clear()
            cache.clear()
            loaded.clear()
            ids
        }
        ids.forEach { CollaborationResearchArchive.remove(appContext, it) }
    }

    companion object {
        private val LOCK = Any()
        private val cache = ConcurrentHashMap<String, CollaborationGroup>()
        private val loaded = ConcurrentHashMap.newKeySet<String>()
        fun cached(conversationId: String): CollaborationGroup? = cache[conversationId]
        fun isLoaded(conversationId: String): Boolean = conversationId in loaded
        fun names(context: Context): List<String> = nameCache ?: synchronized(LOCK) {
            nameCache ?: context.assets.open("collaboration/agent-names.txt").bufferedReader().use {
                CollaborationNamePolicy.validate(it.readLines().map(String::trim).filter(String::isNotEmpty))
            }.also { nameCache = it }
        }
        @Volatile private var nameCache: List<String>? = null
    }
}
