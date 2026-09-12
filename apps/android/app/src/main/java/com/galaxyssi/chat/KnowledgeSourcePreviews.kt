package com.galaxyssi.chat

import android.content.ContentValues
import org.json.JSONObject
import java.nio.ByteBuffer
import java.security.MessageDigest

internal data class KnowledgeSourceHeader(val id: String, val titleKey: String, val sourceKey: String,
    val updated: Long, val ciphertext: String) {
    fun fingerprint(): ByteArray {
        val digest = MessageDigest.getInstance("SHA-256")
        for (value in listOf(id, titleKey, sourceKey, updated.toString(), ciphertext)) {
            val bytes = value.toByteArray(Charsets.UTF_8)
            try { digest.update(ByteBuffer.allocate(4).putInt(bytes.size).array()); digest.update(bytes) }
            finally { bytes.fill(0) }
        }
        return digest.digest()
    }
    fun aad(fingerprint: ByteArray) = "knowledge-source-preview:v1:$id:".toByteArray(Charsets.UTF_8) + fingerprint
}

internal data class AuthenticatedKnowledgeSource(val metadata: KnowledgeSourceMetadata, val sourceKey: String)

/** Derived encrypted metadata; the authoritative header/body format and identities do not change. */
internal object KnowledgeSourcePreviews {
    fun create(db: KnowledgeSqlite) {
        db.execSQL("CREATE TABLE knowledge_source_previews(item_key TEXT PRIMARY KEY REFERENCES knowledge_items(item_key) " +
            "ON DELETE CASCADE,fingerprint BLOB NOT NULL CHECK(typeof(fingerprint)='blob' AND length(fingerprint)=32)," +
            "ciphertext BLOB NOT NULL CHECK(typeof(ciphertext)='blob' AND length(ciphertext)>=29))")
        db.execSQL("CREATE TRIGGER knowledge_source_preview_invalidate AFTER UPDATE OF item_key,title_key,source_key,updated,header " +
            "ON knowledge_items BEGIN DELETE FROM knowledge_source_previews WHERE item_key=OLD.item_key; END")
    }

    fun readHeader(db: KnowledgeSqlite, id: String): KnowledgeSourceHeader? = db.rawQuery(
        "SELECT title_key,source_key,updated,header FROM knowledge_items WHERE item_key=?", arrayOf(id)).use {
        if (!it.moveToFirst()) null else KnowledgeSourceHeader(id, it.getString(0), it.getString(1), it.getLong(2), it.getString(3))
    }

    fun read(db: KnowledgeSqlite, row: KnowledgeSourceHeader, cipher: () -> KnowledgeSourcePreviewCipher): KnowledgeSourceMetadata? =
        db.rawQuery("SELECT fingerprint,ciphertext FROM knowledge_source_previews WHERE item_key=?", arrayOf(row.id)).use {
            if (!it.moveToFirst()) return@use null
            val expected = row.fingerprint()
            check(MessageDigest.isEqual(expected, it.getBlob(0))) { "Source preview does not match current source" }
            val plaintext = cipher().decrypt(it.getBlob(1), row.aad(expected))
            val metadata = try { KnowledgeSourceMetadata.decode(JSONObject(String(plaintext, Charsets.UTF_8))) }
            finally { plaintext.fill(0) }
            check(metadata.updated == row.updated && metadata.source.isBlank() == row.sourceKey.isBlank()) {
                "Source preview metadata mismatch"
            }
            metadata
        }

    // Only the canonical source writer or a fully authenticated legacy read may publish a preview.
    fun putValidated(db: KnowledgeSqlite, row: KnowledgeSourceHeader, metadata: KnowledgeSourceMetadata,
        cipher: KnowledgeSourcePreviewCipher) {
        check(metadata.updated == row.updated && metadata.source.isBlank() == row.sourceKey.isBlank())
        val fingerprint = row.fingerprint()
        val plaintext = metadata.encode().toString().toByteArray(Charsets.UTF_8)
        val encrypted = try { cipher.encrypt(plaintext, row.aad(fingerprint)) } finally { plaintext.fill(0) }
        db.delete("knowledge_source_previews", "item_key=?", arrayOf(row.id))
        db.insertOrThrow("knowledge_source_previews", null, ContentValues().apply {
            put("item_key", row.id); put("fingerprint", fingerprint); put("ciphertext", encrypted)
        })
        db.rawQuery("SELECT changes()", null).use {
            check(it.moveToFirst() && it.getLong(0) == 1L) { "Source preview was not persisted" }
        }
    }
}
