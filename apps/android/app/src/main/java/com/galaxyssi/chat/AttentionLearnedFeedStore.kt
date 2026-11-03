package com.galaxyssi.chat

import android.database.sqlite.SQLiteDatabase

internal data class AttentionSourcePage(val host: String, val url: String, val topics: Set<String>)

/** Public feed membership and polling state; no user credentials or private message content. */
internal object AttentionLearnedFeedStore {
    fun create(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE IF NOT EXISTS learned_news_feeds(url TEXT PRIMARY KEY,host TEXT NOT NULL,next_at INTEGER NOT NULL,last_poll INTEGER NOT NULL DEFAULT 0)")
        db.execSQL("CREATE INDEX IF NOT EXISTS learned_feed_due ON learned_news_feeds(next_at,last_poll)")
        db.execSQL("CREATE TABLE IF NOT EXISTS learned_news_topics(url TEXT NOT NULL,topic TEXT NOT NULL,PRIMARY KEY(url,topic))")
        db.execSQL("CREATE INDEX IF NOT EXISTS learned_feed_topics ON learned_news_topics(topic,url)")
        db.execSQL("CREATE TABLE IF NOT EXISTS news_source_pages(host TEXT PRIMARY KEY,url TEXT NOT NULL,next_at INTEGER NOT NULL DEFAULT 0,status TEXT NOT NULL DEFAULT '')")
        db.execSQL("CREATE INDEX IF NOT EXISTS news_source_due ON news_source_pages(next_at,host)")
        db.execSQL("CREATE TABLE IF NOT EXISTS news_source_topics(host TEXT NOT NULL,topic TEXT NOT NULL,PRIMARY KEY(host,topic))")
    }

    fun pruneDiscussions(db: SQLiteDatabase) {
        val urls = db.rawQuery("SELECT url FROM learned_news_feeds", null).use { c ->
            buildList { while (c.moveToNext()) if (AttentionLearnedFeedPolicy.discussionFeed(c.getString(0))) add(c.getString(0)) }
        }
        urls.forEach { url ->
            db.execSQL("DELETE FROM learned_news_topics WHERE url=?", arrayOf(url))
            db.execSQL("DELETE FROM learned_news_feeds WHERE url=?", arrayOf(url))
        }
    }

    fun observe(db: SQLiteDatabase, url: String, topics: Set<String>) {
        if (!AttentionLearnedFeedPolicy.needsProbe(url)) return
        val host = AttentionLearnedFeedPolicy.host(url)
        db.execSQL("INSERT OR IGNORE INTO news_source_pages(host,url) VALUES(?,?)", arrayOf(host, url))
        topics.forEach { db.execSQL("INSERT OR IGNORE INTO news_source_topics VALUES(?,?)", arrayOf(host, it)) }
    }

    fun backfill(db: SQLiteDatabase): Boolean {
        val cursor = db.rawQuery("SELECT value FROM metadata WHERE id='source_page_cursor'", null).use { if (it.moveToFirst()) it.getString(0) else "" }
        val rows = db.rawQuery("SELECT id,url FROM articles WHERE state='published' AND id>? ORDER BY id LIMIT 256", arrayOf(cursor))
            .use { c -> buildList { while (c.moveToNext()) add(c.getString(0) to c.getString(1)) } }
        db.beginTransaction()
        try {
            rows.forEach { (id, url) -> observe(db, url, AttentionArticleTopics.all(db, id).keys) }
            if (rows.isNotEmpty()) db.execSQL("INSERT OR REPLACE INTO metadata VALUES('source_page_cursor',?)", arrayOf(rows.last().first))
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
        return rows.isNotEmpty()
    }

    fun remember(db: SQLiteDatabase, origin: String, urls: List<String>, topics: Set<String>, now: Long): Set<String> {
        val changed = mutableSetOf<String>()
        db.beginTransaction()
        try {
            for (url in urls.filter { AttentionLearnedFeedPolicy.accepts(origin, it) }.distinct().take(2)) {
                val host = AttentionLearnedFeedPolicy.host(url)
                val count = android.database.DatabaseUtils.longForQuery(db, "SELECT COUNT(*) FROM learned_news_feeds WHERE host=?", arrayOf(host))
                val exists = android.database.DatabaseUtils.longForQuery(db, "SELECT COUNT(*) FROM learned_news_feeds WHERE url=?", arrayOf(url)) > 0
                if (!exists && count >= 2) continue
                db.execSQL("INSERT OR IGNORE INTO learned_news_feeds(url,host,next_at) VALUES(?,?,?)", arrayOf(url, host, now))
                for (topic in topics) {
                    db.execSQL("INSERT OR IGNORE INTO learned_news_topics VALUES(?,?)", arrayOf(url, topic))
                    if (android.database.DatabaseUtils.longForQuery(db, "SELECT changes()", null) > 0) changed += topic
                }
            }
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
        return changed
    }

    fun dueFeed(db: SQLiteDatabase, topic: String, now: Long): String? = db.rawQuery(
        "SELECT f.url FROM learned_news_feeds f JOIN learned_news_topics t ON t.url=f.url WHERE t.topic=? AND f.next_at<=? " +
            "ORDER BY f.last_poll,f.url LIMIT 1", arrayOf(topic, now.toString())).use { if (it.moveToFirst()) it.getString(0) else null }

    fun deferFeed(db: SQLiteDatabase, url: String, until: Long, now: Long) = db.execSQL(
        "UPDATE learned_news_feeds SET next_at=?,last_poll=? WHERE url=?", arrayOf(until, now, url))

    fun feedTopics(db: SQLiteDatabase, url: String): Set<String> = db.rawQuery(
        "SELECT topic FROM learned_news_topics WHERE url=?", arrayOf(url)).use { c -> buildSet { while (c.moveToNext()) add(c.getString(0)) } }

    fun probe(db: SQLiteDatabase, enabled: Set<String>, now: Long): AttentionSourcePage? {
        if (enabled.isEmpty()) return null
        db.beginTransaction()
        try {
            val row = db.rawQuery("SELECT p.host,p.url FROM news_source_pages p WHERE p.next_at<=? AND " +
                "NOT EXISTS(SELECT 1 FROM learned_news_feeds f WHERE f.host=p.host) AND EXISTS(SELECT 1 FROM news_source_topics t " +
                "WHERE t.host=p.host AND t.topic IN (" + enabled.joinToString(",") { "?" } + ")) ORDER BY p.next_at,p.host LIMIT 1",
                arrayOf(now.toString()) + enabled.toTypedArray()).use { c -> if (c.moveToFirst()) c.getString(0) to c.getString(1) else null } ?: return null
            val topics = db.rawQuery("SELECT topic FROM news_source_topics WHERE host=?", arrayOf(row.first)).use { c ->
                buildSet { while (c.moveToNext()) if (c.getString(0) in enabled) add(c.getString(0)) }
            }
            probeDone(db, row.first, now + 5 * 60_000L, "checking")
            db.setTransactionSuccessful()
            return AttentionSourcePage(row.first, row.second, topics)
        } finally { db.endTransaction() }
    }

    fun probeDone(db: SQLiteDatabase, host: String, next: Long, status: String) = db.execSQL(
        "UPDATE news_source_pages SET next_at=?,status=? WHERE host=?", arrayOf(next, status.take(100), host))

    fun nextProbe(db: SQLiteDatabase, enabled: Set<String>): Long? {
        if (enabled.isEmpty()) return null
        return db.rawQuery("SELECT MIN(p.next_at) FROM news_source_pages p WHERE NOT EXISTS(SELECT 1 FROM learned_news_feeds f WHERE f.host=p.host) " +
            "AND EXISTS(SELECT 1 FROM news_source_topics t WHERE t.host=p.host AND t.topic IN (" + enabled.joinToString(",") { "?" } + "))",
            enabled.toTypedArray()).use { if (it.moveToFirst() && !it.isNull(0)) it.getLong(0) else null }
    }
}
