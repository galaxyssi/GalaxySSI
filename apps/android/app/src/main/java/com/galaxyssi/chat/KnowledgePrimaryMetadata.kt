package com.galaxyssi.chat

import android.content.ContentValues

/** Encrypted record headers share the immutable body's commit and lifetime. */
internal object KnowledgePrimaryMetadata {
    private const val PREFIX = "khp1:"
    private const val MAX_HEADER = 4096

    fun create(db: KnowledgeSqlite) = db.execSQL("CREATE TABLE headers(entry_key TEXT PRIMARY KEY," +
        "ciphertext TEXT NOT NULL) WITHOUT ROWID")

    fun hash(encrypted: String): String {
        require(encrypted.length in 1..MAX_HEADER) { "Primary metadata header is oversized" }
        return AgentNativeJsonCodec.sha256(encrypted)
    }

    fun pointer(encrypted: String) = PREFIX + hash(encrypted)
    fun pointerHash(value: String): String? {
        if (!value.startsWith(PREFIX)) return null
        return value.removePrefix(PREFIX).also { require(it.matches(Regex("[a-f0-9]{64}"))) }
    }

    fun write(db: KnowledgeSqlite, entry: String, encrypted: String): Long {
        hash(encrypted)
        // An unpublished copy can replay this row after its body commit but before catalog commit.
        db.delete("headers", "entry_key=?", arrayOf(entry))
        db.insertOrThrow("headers", null, ContentValues().apply { put("entry_key", entry); put("ciphertext", encrypted) })
        return encrypted.length.toLong()
    }

    fun read(db: KnowledgeSqlite, entry: String, expected: String): String {
        require(expected.matches(Regex("[a-f0-9]{64}")))
        val encrypted = db.rawQuery("SELECT substr(ciphertext,1,4097) FROM headers WHERE entry_key=?", arrayOf(entry)).use {
            check(it.moveToFirst()) { "Primary metadata header is missing" }; it.getString(0)
        }
        check(hash(encrypted) == expected) { "Primary metadata header checksum mismatch" }
        return encrypted
    }
}
