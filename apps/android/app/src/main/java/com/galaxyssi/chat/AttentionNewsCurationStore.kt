package com.galaxyssi.chat

import android.database.sqlite.SQLiteDatabase
import java.net.URI
import java.util.Locale

/** Runs on the reader loader, with indexed metadata batches and no full-body/document reads. */
internal object AttentionNewsCurationStore {
    fun decorate(db: SQLiteDatabase, items: List<GlobalProactiveInboxItem>, enabled: Set<String>, now: Long): List<GlobalProactiveInboxItem> {
        val summaries = mutableMapOf<String, AttentionNewsSummary>()
        items.map { it.newsArticleKey }.filter(String::isNotBlank).distinct().chunked(300).forEach { keys ->
            db.rawQuery("SELECT a.id,a.url,a.publisher,a.published,a.collected,a.knowledge,t.topic " +
                "FROM articles a JOIN article_topics t ON t.article_id=a.id WHERE a.state='published' AND a.id IN (" +
                keys.joinToString(",") { "?" } + ") ORDER BY a.id,t.topic", keys.toTypedArray()).use { cursor ->
                while (cursor.moveToNext()) {
                    val topic = cursor.getString(6)
                    if (topic !in enabled) continue
                    val id = cursor.getString(0)
                    val old = summaries[id]
                    if (old != null) summaries[id] = old.copy(topics = old.topics + topic)
                    else {
                        val host = runCatching { URI(cursor.getString(1)).host }.getOrNull()
                        summaries[id] = AttentionNewsSummary((host ?: cursor.getString(2)).lowercase(Locale.ROOT).removePrefix("www."),
                            setOf(topic), cursor.getLong(3), cursor.getLong(4), cursor.getInt(5) != 0)
                    }
                }
            }
        }
        val decorated = items.map { it.copy(newsSummary = summaries[it.newsArticleKey]) }
        val selected = AttentionNewsCuration.select(decorated, now)
        return decorated.map { item -> item.copy(newsSummary = item.newsSummary?.copy(selected = item.key in selected)) }
    }
}
