package com.galaxyssi.chat

import android.content.ContentValues
import android.database.sqlite.SQLiteDatabase
import java.io.Closeable
import java.io.File
import org.json.JSONObject

/** Only encrypted rows and local blind-index keys are written to the temporary database. */
internal class HealthRestoreStage(file: File, private val batch: String) : Closeable {
    private val db = SQLiteDatabase.openOrCreateDatabase(file, null)
    private var nextSource = 0L
    init {
        try {
            db.execSQL("CREATE TABLE items(id TEXT PRIMARY KEY,kind TEXT NOT NULL,dedupe TEXT,evidence TEXT,payload BLOB NOT NULL)")
            db.execSQL("CREATE INDEX staged_restore_kind ON items(kind,id)")
            db.execSQL("CREATE UNIQUE INDEX staged_restore_dedupe ON items(dedupe) WHERE kind='NEW' AND dedupe IS NOT NULL")
            db.execSQL("CREATE UNIQUE INDEX staged_restore_evidence ON items(evidence) WHERE kind='NEW' AND evidence IS NOT NULL")
            db.execSQL("CREATE TABLE source_links(seq INTEGER PRIMARY KEY,slot TEXT UNIQUE,conflict_id TEXT,payload BLOB NOT NULL)")
            db.execSQL("CREATE INDEX staged_restore_source_conflict ON source_links(conflict_id,seq)")
        } catch (failure: Throwable) {
            db.close()
            throw failure
        }
    }

    fun <T> fill(block: () -> T): T {
        db.beginTransaction()
        return try { block().also { db.setTransactionSuccessful() } } finally { db.endTransaction() }
    }

    private fun aad(id: String, kind: HealthRestoreKind) = "health-restore-stage-v1|$batch|$id|${kind.name}".toByteArray(Charsets.UTF_8)

    private fun decode(id: String, kind: HealthRestoreKind, data: ByteArray): HealthRestoreConflict {
        val bytes = AgentStorageCipher.decryptBinary(data, aad(id, kind))
        return try {
            val value = JSONObject(String(bytes, Charsets.UTF_8))
            val row = HealthObservation.from(value.getJSONObject("incoming"))
            check(row.id == id)
            HealthRestoreConflict(row, value.optJSONObject("existing")?.let(HealthObservation::from), value.optBoolean("deleted"), value.optBoolean("replaceable"))
        } finally { bytes.fill(0) }
    }

    fun colliding(dedupe: String?, evidence: String?): HealthObservation? {
        fun find(column: String, key: String?) = key?.let {
            db.rawQuery("SELECT id,payload FROM items WHERE kind='NEW' AND $column=?", arrayOf(it)).use { row ->
                if (row.moveToFirst()) decode(row.getString(0), HealthRestoreKind.NEW, row.getBlob(1)).record else null
            }
        }
        return find("evidence", evidence) ?: find("dedupe", dedupe)
    }

    fun add(record: HealthObservation, match: HealthRestoreMatch, dedupe: String?, evidence: String?, replaceable: Boolean = false) {
        if (match.kind == HealthRestoreKind.DUPLICATE) return
        val data = JSONObject().put("incoming", record.json()).put("deleted", match.deleted).put("replaceable", replaceable)
        match.existing?.let { data.put("existing", it.json()) }
        val bytes = data.toString().toByteArray(Charsets.UTF_8)
        try {
            val sealed = AgentStorageCipher.encryptBinary(bytes, aad(record.id, match.kind))
            db.insertOrThrow("items", null, ContentValues().apply {
                put("id", record.id); put("kind", match.kind.name); put("dedupe", dedupe); put("evidence", evidence); put("payload", sealed)
            })
        } finally { bytes.fill(0) }
    }

    fun conflicts(after: String): HealthRestoreConflictPage {
        val rows = page(HealthRestoreKind.CONFLICT, after)
        return HealthRestoreConflictPage(rows.take(30), rows.getOrNull(30)?.let { rows[29].record.id })
    }

    fun conflict(id: String): HealthRestoreConflict? = db.rawQuery("SELECT payload FROM items WHERE kind='CONFLICT' AND id=?", arrayOf(id))
        .use { if (it.moveToFirst()) decode(id, HealthRestoreKind.CONFLICT, it.getBlob(0)) else null }

    fun newRecords(): Sequence<HealthObservation> = sequence {
        var after = ""
        while (true) {
            val rows = page(HealthRestoreKind.NEW, after).take(30)
            if (rows.isEmpty()) break
            for (row in rows) yield(row.record)
            after = rows.last().record.id
        }
    }

    private fun sourceAad(seq: Long, conflictId: String?) = "health-restore-source-v1|$batch|$seq|${conflictId.orEmpty()}".toByteArray(Charsets.UTF_8)

    private fun decodeSource(seq: Long, sealed: ByteArray, conflictId: String? = null): HealthRestoreSourceLink {
        val bytes = AgentStorageCipher.decryptBinary(sealed, sourceAad(seq, conflictId))
        return try { HealthRestoreSourceLink.from(JSONObject(String(bytes, Charsets.UTF_8))) } finally { bytes.fill(0) }
    }

    fun stageSource(link: HealthRestoreSourceLink, conflictId: String? = null) {
        val seq = ++nextSource
        val bytes = link.json().toString().toByteArray(Charsets.UTF_8)
        val sealed = try { AgentStorageCipher.encryptBinary(bytes, sourceAad(seq, conflictId)) } finally { bytes.fill(0) }
        try {
            db.insertOrThrow("source_links", null, ContentValues().apply { put("seq", seq); put("payload", sealed); put("conflict_id", conflictId) })
        } finally { sealed.fill(0) }
    }

    fun sourceLinks(planned: Boolean = false, conflictId: String? = null): Sequence<Pair<Long, HealthRestoreSourceLink>> = sequence {
        var after = 0L
        val filter = (if (conflictId == null) " AND conflict_id IS NULL" else " AND conflict_id=?") +
            if (planned) " AND slot IS NOT NULL" else ""
        while (true) {
            val rows = db.rawQuery("SELECT seq,payload FROM source_links WHERE seq>?$filter ORDER BY seq LIMIT 30",
                if (conflictId == null) arrayOf(after.toString()) else arrayOf(after.toString(), conflictId)).use { cursor -> buildList {
                    while (cursor.moveToNext()) add(cursor.getLong(0).let { it to decodeSource(it, cursor.getBlob(1), conflictId) })
                } }
            if (rows.isEmpty()) break
            yieldAll(rows)
            after = rows.last().first
        }
    }

    fun planSource(seq: Long, slot: String, link: HealthRestoreSourceLink): HealthRestoreKind {
        db.rawQuery("SELECT seq,payload FROM source_links WHERE slot=?", arrayOf(slot)).use { cursor ->
            if (cursor.moveToFirst()) return if (decodeSource(cursor.getLong(0), cursor.getBlob(1)) == link)
                HealthRestoreKind.DUPLICATE else HealthRestoreKind.CONFLICT
        }
        check(db.update("source_links", ContentValues().apply { put("slot", slot) }, "seq=? AND slot IS NULL", arrayOf(seq.toString())) == 1)
        return HealthRestoreKind.NEW
    }

    private fun page(kind: HealthRestoreKind, after: String) =
        db.rawQuery("SELECT id,payload FROM items WHERE kind=? AND id>? ORDER BY id LIMIT 31", arrayOf(kind.name, after))
            .use { cursor -> buildList { while (cursor.moveToNext()) add(decode(cursor.getString(0), kind, cursor.getBlob(1))) } }

    override fun close() = db.close()
}
