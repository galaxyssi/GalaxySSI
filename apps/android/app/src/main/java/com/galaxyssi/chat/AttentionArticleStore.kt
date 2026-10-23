package com.galaxyssi.chat

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import java.util.concurrent.ConcurrentHashMap

internal data class AttentionArticleJob(val key: String, val url: String, val topic: String, val topicTitle: String,
    val title: String, val publisher: String, val published: Long, val collected: Long, val attempts: Int,
    val state: String, val chineseTitle: String = "", val preview: String = "", val provider: String = "")

/** Public news only. Queue metadata is indexed; full Chinese bodies are read individually on demand. */
internal class AttentionArticleStore(context: Context, name: String = NAME) {
    private val helper = helpers.computeIfAbsent(context.getDatabasePath(name).absolutePath) { Helper(context.applicationContext, name) }
    private val db get() = helper.writableDatabase

    fun enqueue(article: AttentionFeedArticle, topicTitle: String) {
        db.insertWithOnConflict("articles", null, ContentValues().apply {
            put("id", article.key); put("url", article.url); put("topic", article.topicId); put("topic_title", topicTitle)
            put("title", article.title); put("publisher", AttentionFeedCollectionPlan.publisher(article.url, article.publisher))
            put("published", if (article.discoveryDate) 0L else article.publishedAt)
            put("collected", article.collectedAt)
        }, SQLiteDatabase.CONFLICT_IGNORE)
    }

    fun importLegacy(feed: ProactiveAttentionFeedStore, topics: List<AttentionTopic>): Boolean {
        if (meta("legacy_done") == "1") return false
        val records = feed.articleRecordsAfter(meta("legacy_cursor"), 256)
        val topicNames = topics.associate { it.id to it.title }
        db.beginTransaction()
        try {
            for (r in records) enqueue(AttentionFeedArticle(r.getString("key"), r.optString("topic"), r.optString("title"),
                "", r.optString("url"), r.optString("publisher"), r.optLong("published"), r.optLong("collected"),
                discoveryDate = r.optBoolean("discovery_date")),
                topicNames[r.optString("topic")].orEmpty())
            if (records.isEmpty()) putMeta("legacy_done", "1")
            else putMeta("legacy_cursor", "article:" + records.last().getString("key"))
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
        return records.isNotEmpty()
    }

    fun claim(topics: Set<String>, now: Long): AttentionArticleJob? {
        if (topics.isEmpty()) return null
        db.beginTransaction()
        try {
            val filter = topics.joinToString(",") { "?" }
            val args = arrayOf(now.toString()) + topics.toTypedArray()
            val job = db.rawQuery("SELECT $COLUMNS FROM articles WHERE state <> 'published' AND next_at <= ? " +
                "AND topic IN ($filter) ORDER BY CASE state WHEN 'ready' THEN 0 WHEN 'repair' THEN 1 ELSE 2 END," +
                "CAST(COALESCE((SELECT value FROM metadata WHERE id = 'claimed:' || articles.publisher),'0') AS INTEGER)," +
                "collected DESC,id LIMIT 1", args)
                .use { if (it.moveToFirst()) readJob(it) else null } ?: return null
            db.execSQL("UPDATE articles SET next_at = ?, attempts = attempts + 1 WHERE id = ?", arrayOf(now + 5 * 60_000, job.key))
            putMeta("claimed:" + job.publisher, now.toString())
            db.setTransactionSuccessful()
            return job
        } finally { db.endTransaction() }
    }

    fun ready(key: String, article: AttentionChineseArticle) {
        require(article.title.isNotBlank() && article.body.length >= 80)
        db.update("articles", ContentValues().apply {
            put("state", "ready"); put("zh_title", article.title); put("body", article.body)
            put("preview", article.body.take(500)); put("provider", article.provider); put("error", ""); put("next_at", 0)
        }, "id = ?", arrayOf(key))
    }

    fun published(key: String) { db.execSQL("UPDATE articles SET state = 'published', error = '' WHERE id = ?", arrayOf(key)) }
    fun failed(job: AttentionArticleJob, error: String, now: Long) {
        val delay = (30_000L * (1L shl job.attempts.coerceIn(0, 9))).coerceAtMost(4 * 60 * 60_000L)
        db.execSQL("UPDATE articles SET next_at = ?, error = ? WHERE id = ?", arrayOf(now + delay, error.take(120), job.key))
    }

    fun metadata(key: String): AttentionArticleJob? = db.rawQuery("SELECT $COLUMNS FROM articles WHERE id = ?", arrayOf(key))
        .use { if (it.moveToFirst()) readJob(it) else null }

    fun body(key: String): String? = db.rawQuery("SELECT body FROM articles WHERE id = ? AND state IN ('ready','published')", arrayOf(key))
        .use { if (it.moveToFirst()) it.getString(0) else null }

    fun nextAt(topics: Set<String>): Long? {
        if (topics.isEmpty()) return null
        return db.rawQuery("SELECT MIN(next_at) FROM articles WHERE state <> 'published' AND topic IN (" +
            topics.joinToString(",") { "?" } + ")", topics.toTypedArray()).use {
            if (it.moveToFirst() && !it.isNull(0)) it.getLong(0) else null
        }
    }

    private fun meta(key: String) = db.rawQuery("SELECT value FROM metadata WHERE id = ?", arrayOf(key))
        .use { if (it.moveToFirst()) it.getString(0) else "" }
    private fun putMeta(key: String, value: String) = db.execSQL("INSERT OR REPLACE INTO metadata VALUES(?,?)", arrayOf(key, value))
    private fun readJob(c: Cursor) = AttentionArticleJob(c.getString(0), c.getString(1), c.getString(2), c.getString(3),
        c.getString(4), c.getString(5), c.getLong(6), c.getLong(7),
        c.getInt(8), c.getString(9), c.getString(10), c.getString(11), c.getString(12))

    private class Helper(context: Context, name: String) : SQLiteOpenHelper(context, name, null, 3) {
        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE articles(id TEXT PRIMARY KEY NOT NULL,url TEXT NOT NULL,topic TEXT NOT NULL," +
                "topic_title TEXT NOT NULL,title TEXT NOT NULL,publisher TEXT NOT NULL,published INTEGER NOT NULL," +
                "collected INTEGER NOT NULL,attempts INTEGER NOT NULL DEFAULT 0,state TEXT NOT NULL DEFAULT 'pending'," +
                "next_at INTEGER NOT NULL DEFAULT 0,error TEXT NOT NULL DEFAULT '',zh_title TEXT NOT NULL DEFAULT ''," +
                "preview TEXT NOT NULL DEFAULT '',body TEXT NOT NULL DEFAULT '',provider TEXT NOT NULL DEFAULT '')")
            db.execSQL("CREATE INDEX article_queue ON articles(state,next_at,topic,collected DESC)")
            db.execSQL("CREATE TABLE metadata(id TEXT PRIMARY KEY NOT NULL,value TEXT NOT NULL)")
        }
        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
            if (oldVersion < 3) {
                // Re-extract early development bodies containing page chrome. Preserve discoveries and inbox read state.
                db.execSQL("UPDATE articles SET state = CASE WHEN state IN ('ready','published') THEN 'repair' ELSE 'pending' END," +
                    "next_at = 0,attempts = 0,error = '',body = '',preview = ''")
            }
        }
    }

    companion object {
        const val NAME = "attention_public_articles_v1.db"
        private const val COLUMNS = "id,url,topic,topic_title,title,publisher,published,collected,attempts,state,zh_title,preview,provider"
        private val helpers = ConcurrentHashMap<String, Helper>()
        internal fun closeTest(context: Context, name: String) {
            require(name != NAME)
            helpers.remove(context.getDatabasePath(name).absolutePath)?.close()
        }
    }
}
