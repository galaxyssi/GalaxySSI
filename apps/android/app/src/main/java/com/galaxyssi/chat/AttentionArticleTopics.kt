package com.galaxyssi.chat

import android.database.sqlite.SQLiteDatabase

/** One article/body, multiple subscriptions. Joins never duplicate the publication or read state. */
internal object AttentionArticleTopics {
    fun create(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE IF NOT EXISTS article_topics(article_id TEXT NOT NULL,topic TEXT NOT NULL," +
            "title TEXT NOT NULL,PRIMARY KEY(article_id,topic))")
        db.execSQL("CREATE INDEX IF NOT EXISTS article_topics_lookup ON article_topics(topic,article_id)")
        db.execSQL("INSERT OR IGNORE INTO article_topics SELECT id,topic,topic_title FROM articles")
    }

    fun add(db: SQLiteDatabase, key: String, topic: String, title: String) {
        db.execSQL("INSERT OR REPLACE INTO article_topics(article_id,topic,title) VALUES(?,?,?)", arrayOf(key, topic, title))
    }

    fun filter(topics: Set<String>): String {
        require(topics.isNotEmpty())
        return "EXISTS (SELECT 1 FROM article_topics t WHERE t.article_id=articles.id AND t.topic IN (" +
            topics.joinToString(",") { "?" } + "))"
    }

    fun all(db: SQLiteDatabase, key: String): Map<String, String> = db.rawQuery(
        "SELECT topic,title FROM article_topics WHERE article_id=? ORDER BY topic", arrayOf(key)).use { cursor ->
        buildMap { while (cursor.moveToNext()) put(cursor.getString(0), cursor.getString(1)) }
    }

    fun scope(db: SQLiteDatabase, job: AttentionArticleJob, enabled: Set<String>): AttentionArticleJob? {
        val matches = all(db, job.key).filterKeys { it in enabled }
        val selected = matches[job.topic]?.let { job.topic } ?: matches.keys.firstOrNull() ?: return null
        return job.copy(topic = selected, topicTitle = matches.getValue(selected))
    }
}
