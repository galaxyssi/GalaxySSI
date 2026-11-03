package com.galaxyssi.chat

import android.database.sqlite.SQLiteDatabase

internal interface AttentionTranslationProgress {
    fun read(source: String): String?
    fun save(source: String, translated: String)
}

/** Public article staging only. Partial translations are never exposed as published articles. */
internal object AttentionArticleCheckpoint {
    private const val REVISION = 1
    private const val MAX_AGE = 24 * 60 * 60_000L
    fun create(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE IF NOT EXISTS article_extraction(id TEXT PRIMARY KEY,title TEXT NOT NULL,document TEXT NOT NULL," +
            "fingerprint TEXT NOT NULL,revision INTEGER NOT NULL,created INTEGER NOT NULL)")
        db.execSQL("CREATE TABLE IF NOT EXISTS article_translation_progress(article_id TEXT NOT NULL,hash TEXT NOT NULL," +
            "source TEXT NOT NULL,translated TEXT NOT NULL,PRIMARY KEY(article_id,hash))")
    }

    fun source(db: SQLiteDatabase, id: String, now: Long): AttentionArticleSource? = db.rawQuery(
        "SELECT title,document FROM article_extraction WHERE id=? AND revision=? AND created>=?",
        arrayOf(id, REVISION.toString(), (now - MAX_AGE).toString())).use { cursor ->
        if (!cursor.moveToFirst()) return null
        val document = AttentionArticleDocument.decode(cursor.getString(1)) ?: return null
        AttentionArticleSource(AgentPublicArticle(cursor.getString(0), "", "", document.body, emptyList(), emptyList(), "checkpoint"), document)
    }

    fun save(db: SQLiteDatabase, id: String, source: AttentionArticleSource, now: Long) {
        val document = source.document.encode()
        val fingerprint = ProactiveAttentionFeedPolicy.urlKey(source.article.title + "\u0000" + document)
        db.beginTransaction()
        try {
            val previous = db.rawQuery("SELECT fingerprint FROM article_extraction WHERE id=?", arrayOf(id)).use {
                if (it.moveToFirst()) it.getString(0) else ""
            }
            if (previous != fingerprint) db.execSQL("DELETE FROM article_translation_progress WHERE article_id=?", arrayOf(id))
            db.execSQL("INSERT OR REPLACE INTO article_extraction VALUES(?,?,?,?,?,?)",
                arrayOf(id, source.article.title, document, fingerprint, REVISION, now))
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
    }

    fun progress(db: SQLiteDatabase, id: String) = object : AttentionTranslationProgress {
        override fun read(source: String): String? = db.rawQuery(
            "SELECT source,translated FROM article_translation_progress WHERE article_id=? AND hash=?",
            arrayOf(id, ProactiveAttentionFeedPolicy.urlKey(source))).use {
            if (it.moveToFirst() && it.getString(0) == source) it.getString(1) else null
        }
        override fun save(source: String, translated: String) {
            if (read(source) == translated) return
            db.execSQL("INSERT OR REPLACE INTO article_translation_progress VALUES(?,?,?,?)",
                arrayOf(id, ProactiveAttentionFeedPolicy.urlKey(source), source, translated))
        }
    }

    fun progressCount(db: SQLiteDatabase, id: String): Long = android.database.DatabaseUtils.longForQuery(db,
        "SELECT COUNT(*) FROM article_translation_progress WHERE article_id=?", arrayOf(id))

    fun complete(db: SQLiteDatabase, id: String) {
        db.execSQL("DELETE FROM article_extraction WHERE id=?", arrayOf(id))
        db.execSQL("DELETE FROM article_translation_progress WHERE article_id=?", arrayOf(id))
    }
}
