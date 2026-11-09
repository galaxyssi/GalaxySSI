package com.galaxyssi.chat

import android.content.ContentValues
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import org.json.JSONObject

internal class HealthCareDocumentRows(private val db: SQLiteDatabase,
    private val pack: (String, String, JSONObject) -> ByteArray, private val unpack: (String, String, ByteArray) -> JSONObject,
    private val key: (String) -> String) {
    private fun fingerprint(source: HealthCareDocumentRef) = key(source.json().toString())
    private fun decode(row: Cursor) = HealthCareDocumentLink.from(unpack("encounter_document", row.getString(0), row.getBlob(5))).also {
        check(it.id == row.getString(0) && it.concernId == row.getString(1) && it.encounterId == row.getString(2) &&
            it.revision == row.getInt(3) && fingerprint(it.source) == row.getString(4))
    }
    fun get(id: String): HealthCareDocumentLink? {
        require(HealthProfilePolicy.uuid(id))
        return db.rawQuery("SELECT $COLUMNS FROM encounter_documents WHERE id=?", arrayOf(id)).use { if (it.moveToFirst()) decode(it) else null }
    }
    fun matching(encounterId: String, source: HealthCareDocumentRef) = db.rawQuery(
        "SELECT $COLUMNS FROM encounter_documents WHERE encounter_id=? AND source_key=?", arrayOf(encounterId, fingerprint(source)))
        .use { if (it.moveToFirst()) decode(it) else null }
    fun write(link: HealthCareDocumentLink) {
        check(db.insertOrThrow("encounter_documents", null, ContentValues().apply {
            put("id", link.id); put("concern_id", link.concernId); put("encounter_id", link.encounterId); put("revision", link.revision)
            put("source_key", fingerprint(link.source)); put("payload", pack("encounter_document", link.id, link.json()))
        }) != -1L) { "Encounter document write failed" }
    }
    fun page(concernId: String, encounterId: String, before: Int, limit: Int): HealthCareDocumentPage {
        require(HealthProfilePolicy.uuid(concernId) && HealthProfilePolicy.uuid(encounterId) && before > 0 && limit in 1..30)
        val rows = db.rawQuery("SELECT $COLUMNS FROM encounter_documents WHERE concern_id=? AND encounter_id=? AND revision<? " +
            "ORDER BY revision DESC LIMIT ${limit + 1}", arrayOf(concernId, encounterId, before.toString())).use { row ->
            buildList { while (row.moveToNext()) add(decode(row)) }
        }
        return HealthCareDocumentPage(rows.take(limit), if (rows.size > limit) rows[limit - 1].revision else null)
    }
    fun remove(id: String) { check(db.delete("encounter_documents", "id=?", arrayOf(id)) == 1) }
    fun purge(concernId: String, encounterId: String? = null) {
        db.delete("encounter_documents", "concern_id=?" + if (encounterId == null) "" else " AND encounter_id=?",
            listOfNotNull(concernId, encounterId).toTypedArray())
    }
    companion object {
        private const val COLUMNS = "id,concern_id,encounter_id,revision,source_key,payload"
        fun create(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE encounter_documents(id TEXT PRIMARY KEY,concern_id TEXT NOT NULL,encounter_id TEXT NOT NULL," +
                "revision INTEGER NOT NULL,source_key TEXT NOT NULL,payload BLOB NOT NULL,UNIQUE(encounter_id,source_key))")
            db.execSQL("CREATE INDEX care_encounter_documents ON encounter_documents(concern_id,encounter_id,revision DESC)")
        }
    }
}
