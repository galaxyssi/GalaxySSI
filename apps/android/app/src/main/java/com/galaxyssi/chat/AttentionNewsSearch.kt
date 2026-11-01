package com.galaxyssi.chat

import android.database.sqlite.SQLiteDatabase
import android.os.CancellationSignal

internal enum class AttentionNewsScope { ALL, UNREAD, SAVED }
internal enum class AttentionNewsSort { RELEVANCE, NEWEST }
internal data class AttentionNewsQuery(
    val text: String, val scope: AttentionNewsScope = AttentionNewsScope.ALL,
    val source: String = "", val since: Long = 0, val sort: AttentionNewsSort = AttentionNewsSort.RELEVANCE,
    val snapshot: Long = System.currentTimeMillis()
)
internal data class AttentionNewsSearchState(val viewed: Map<String, Long>, val saved: Set<String>) {
    fun includes(id: String, scope: AttentionNewsScope) = id in viewed && when (scope) {
        AttentionNewsScope.ALL -> true
        AttentionNewsScope.UNREAD -> (viewed[id] ?: 0L) <= 0L
        AttentionNewsScope.SAVED -> itemKey(id) in saved
    }
    companion object { fun itemKey(id: String) = "global-agent:attention-feed:$id" }
}
internal data class AttentionNewsHit(val id: String, val title: String, val snippet: String, val source: String,
    val url: String, val topic: String, val published: Long, val collected: Long, val viewed: Long, val saved: Boolean) {
    fun item() = GlobalProactiveInboxItem(AttentionNewsSearchState.itemKey(id), setOf("attention-feed:$id"),
        title, snippet, topic, GlobalProactiveTarget.NEW_CONVERSATION, false, "", "", emptySet(),
        collected, published.takeIf { it > 0 } ?: collected, viewed, null, newsArticleKey = id)
}
internal data class AttentionNewsPage(val hits: List<AttentionNewsHit>, val total: Int, val offset: Int) {
    val hasMore get() = offset + hits.size < total
}

internal object AttentionNewsSearchPolicy {
    const val PAGE_SIZE = 30
    const val MAX_QUERY = 256
    fun terms(text: String) = text.trim().split(Regex("\\s+")).filter(String::isNotBlank).distinct()
    fun pattern(text: String) = "%" + text.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"
    fun ranges(text: String, query: String): List<IntRange> = terms(query).flatMap { term ->
        buildList {
            var from = 0
            while (from < text.length) {
                val index = text.indexOf(term, from, ignoreCase = true)
                if (index < 0) break
                add(index until index + term.length); from = index + term.length
            }
        }
    }
}

/** Cancellable SQL matching supports literal CJK substrings as well as Latin words. Only IDs are
 * streamed for counting/filtering; bodies never leave SQLite except for the current page snippets. */
internal object AttentionNewsSearchSql {
    fun query(db: SQLiteDatabase, query: AttentionNewsQuery, state: AttentionNewsSearchState,
        offset: Int, signal: CancellationSignal): AttentionNewsPage {
        require(offset >= 0 && query.text.length <= AttentionNewsSearchPolicy.MAX_QUERY)
        val terms = AttentionNewsSearchPolicy.terms(query.text)
        if (terms.isEmpty()) return AttentionNewsPage(emptyList(), 0, offset)
        signal.throwIfCanceled()
        val args = mutableListOf(query.snapshot.toString(), query.since.coerceAtLeast(0).toString())
        // rawQuery binds strings; CASE has no column affinity to coerce the time boundary.
        val where = StringBuilder("state = 'published' AND length(body)>0 AND length(zh_title)>0 AND collected<=? " +
            "AND CASE WHEN published>0 THEN published ELSE collected END >= CAST(? AS INTEGER)")
        if (query.source.isNotBlank()) { where.append(" AND publisher=?"); args += query.source }
        val columns = listOf("zh_title", "title", "body", "publisher", "topic_title")
        terms.forEach { term ->
            where.append(" AND (").append(columns.joinToString(" OR ") { "$it LIKE ? ESCAPE '\\'" }).append(")")
            repeat(columns.size) { args += AttentionNewsSearchPolicy.pattern(term) }
        }
        val rank = if (query.sort == AttentionNewsSort.RELEVANCE) terms.joinToString("+") { term ->
            repeat(2) { args += AttentionNewsSearchPolicy.pattern(term) }
            "(CASE WHEN zh_title LIKE ? ESCAPE '\\' THEN 10 ELSE 0 END + " +
                "CASE WHEN publisher LIKE ? ESCAPE '\\' THEN 3 ELSE 0 END)"
        } else "0"
        val order = (if (query.sort == AttentionNewsSort.RELEVANCE) "($rank) DESC," else "") +
            "CASE WHEN published>0 THEN published ELSE collected END DESC,id DESC"
        val ids = ArrayList<String>(AttentionNewsSearchPolicy.PAGE_SIZE)
        var count = 0
        db.rawQuery("SELECT id FROM articles WHERE $where ORDER BY $order", args.toTypedArray(), signal).use { c ->
            while (c.moveToNext()) {
                signal.throwIfCanceled()
                val id = c.getString(0)
                if (!state.includes(id, query.scope)) continue
                if (count >= offset && ids.size < AttentionNewsSearchPolicy.PAGE_SIZE) ids += id
                count++
            }
        }
        if (ids.isEmpty()) return AttentionNewsPage(emptyList(), count, offset)
        val placeholders = ids.joinToString(",") { "?" }
        val snippet = "CASE WHEN instr(lower(body),lower(?))>0 THEN " +
            "substr(body,max(1,instr(lower(body),lower(?))-48),220) ELSE substr(preview,1,220) END"
        val pageArgs = (listOf(terms.first(), terms.first()) + ids).toTypedArray()
        val hits = db.rawQuery("SELECT id,zh_title,$snippet,publisher,url,topic_title,published,collected " +
            "FROM articles WHERE id IN ($placeholders)", pageArgs, signal).use { c -> buildMap {
            while (c.moveToNext()) {
                signal.throwIfCanceled()
                val id = c.getString(0)
                put(id, AttentionNewsHit(id, c.getString(1), c.getString(2), c.getString(3), c.getString(4),
                    c.getString(5), c.getLong(6), c.getLong(7), state.viewed[id] ?: 0L,
                    AttentionNewsSearchState.itemKey(id) in state.saved))
            }
        } }
        return AttentionNewsPage(ids.mapNotNull(hits::get), count, offset)
    }
}
