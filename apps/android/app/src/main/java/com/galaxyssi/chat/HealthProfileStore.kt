package com.galaxyssi.chat

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import java.io.Closeable
import java.util.UUID
import org.json.JSONObject

/** Self-reported context has its own encrypted rows, never measurement or generic memory records. */
internal class HealthProfileStore(private val context: Context, private val name: String = DEFAULT_DB,
    private val privacyDatabase: String = HealthPrivacyStore.DEFAULT_DB) : Closeable {
    private val helper = Database(context, name); private val db get() = helper.writableDatabase
    private fun aad(kind: String, key: String) = "$name|health-profile-v1|self|$kind|$key".toByteArray(Charsets.UTF_8)
    private fun pack(kind: String, key: String, json: JSONObject): ByteArray {
        val bytes = json.toString().toByteArray(Charsets.UTF_8)
        return try { AgentStorageCipher.encryptBinary(bytes, aad(kind, key)) } finally { bytes.fill(0) }
    }
    private fun unpack(kind: String, key: String, bytes: ByteArray): JSONObject {
        val plain = AgentStorageCipher.decryptBinary(bytes, aad(kind, key))
        return try { JSONObject(String(plain, Charsets.UTF_8)) } finally { plain.fill(0) }
    }
    @Synchronized private fun <T> transaction(notify: Boolean = false, block: () -> T): T {
        db.beginTransactionNonExclusive(); var committed = false
        return try { block().also { db.setTransactionSuccessful(); committed = true } }
        finally { db.endTransaction(); if (committed && notify) runCatching { context.contentResolver.notifyChange(changes(context, name), null) } }
    }
    private fun clock(key: String): String = db.rawQuery("SELECT token,payload FROM clocks WHERE key=?", arrayOf(key)).use {
        if (!it.moveToFirst()) "" else it.getString(0).also { token -> val j = unpack("clock", "$key:$token", it.getBlob(1)); check(j.getString("key") == key && j.getString("token") == token) }
    }
    private fun tick(key: String): String = UUID.randomUUID().toString().also { token -> db.insertWithOnConflict("clocks", null, ContentValues().apply {
        put("key", key); put("token", token); put("payload", pack("clock", "$key:$token", JSONObject().put("key", key).put("token", token)))
    }, SQLiteDatabase.CONFLICT_REPLACE) }
    private fun generation() = clock("generation")
    fun currentGeneration(): String = transaction { generation() }
    private fun requireGeneration(expected: String) { if (generation() != expected) throw HealthProfileConflict() }
    private fun cell(field: HealthProfileField): HealthProfileCell {
        val token = clock("field:${field.name}")
        return db.rawQuery("SELECT token,updated_at,payload FROM basics WHERE field=?", arrayOf(field.name)).use {
            if (!it.moveToFirst()) HealthProfileCell(null, token, 0) else {
                check(token.isNotEmpty() && token == it.getString(0)); val time = it.getLong(1)
                val j = unpack("basic", "${field.name}:$token", it.getBlob(2)); val input = HealthProfileInput.from(j.getJSONObject("value"))
                check(j.getString("field") == field.name && j.getString("source") == "self_reported" && j.getLong("updated") == time)
                check(HealthProfilePolicy.normalize(field, input, java.time.LocalDate.of(9999, 12, 31)) == input)
                HealthProfileCell(input, token, time)
            }
        }
    }
    fun snapshot(): HealthProfileSnapshot = transaction {
        HealthProfileSnapshot(generation(), HealthProfileField.entries.associateWith(::cell), HealthBackgroundKind.entries.associateWith(::count), basicDraft(), clock("profile"))
    }
    fun basicDraft(): HealthProfileDraft? = readDraft("basic")?.let(HealthProfileDraft::from)?.also(HealthProfilePolicy::validateDraft)
    private fun readDraft(key: String): JSONObject? = db.rawQuery("SELECT payload FROM drafts WHERE id=?", arrayOf(key)).use { if (it.moveToFirst()) unpack("draft", key, it.getBlob(0)) else null }
    private fun putDraft(key: String, value: JSONObject) { db.insertWithOnConflict("drafts", null, ContentValues().apply { put("id", key); put("payload", pack("draft", key, value)) }, SQLiteDatabase.CONFLICT_REPLACE); tick("drafts") }
    fun draft(value: HealthProfileDraft) = transaction(true) {
        requireGeneration(value.generation); HealthProfilePolicy.validateDraft(value)
        val prior = basicDraft()
        if (prior != null && (prior.generation != value.generation || value.expected.any { (field, token) -> prior.expected[field]?.let { it != token } == true })) throw HealthProfileConflict()
        putDraft("basic", value.copy(changes = prior?.changes.orEmpty() + value.changes, expected = prior?.expected.orEmpty() + value.expected).json())
    }
    fun restoreBasicField(field: HealthProfileField, before: HealthProfileDraft?, generation: String, observed: HealthProfileInput?) = transaction(true) {
        requireGeneration(generation); val current = basicDraft() ?: return@transaction
        if (current.changes[field] != observed && current.changes[field] != before?.changes?.get(field)) throw HealthProfileConflict()
        val changes = current.changes.toMutableMap().apply { remove(field); before?.changes?.get(field)?.let { put(field, it) } }
        val expected = current.expected.toMutableMap().apply { remove(field); before?.expected?.get(field)?.let { put(field, it) } }
        if (changes.isEmpty()) { db.delete("drafts", "id='basic'", null); tick("drafts") }
        else putDraft("basic", current.copy(changes = changes, expected = expected).json())
    }
    fun discardBasic(generation: String) = transaction(true) { requireGeneration(generation); db.delete("drafts", "id='basic'", null); tick("drafts") }
    fun saveBasics(value: HealthProfileDraft) = transaction(true) {
        requireGeneration(value.generation); HealthProfilePolicy.validateDraft(value)
        val normalized = value.changes.mapValues { (field, input) -> HealthProfilePolicy.normalize(field, input) }
        val current = value.changes.keys.associateWith(::cell)
        if (value.expected.any { (field, token) -> current.getValue(field).token != token }) throw HealthProfileConflict()
        var changed = false
        normalized.forEach { (field, input) -> if (input != current.getValue(field).value) {
            val token = tick("field:${field.name}"); db.delete("basics", "field=?", arrayOf(field.name))
            if (input != null) { val time = System.currentTimeMillis(); db.insertOrThrow("basics", null, ContentValues().apply {
                put("field", field.name); put("token", token); put("updated_at", time)
                put("payload", pack("basic", "${field.name}:$token", JSONObject().put("field", field.name).put("source", "self_reported").put("updated", time).put("value", input.json())))
            }) }; changed = true
        } }
        basicDraft()?.let { draft ->
            val saved = value.changes.keys.filter { draft.changes[it] == value.changes[it] && draft.expected[it] == value.expected[it] }.toSet()
            val remaining = draft.changes - saved
            if (remaining.isEmpty()) { db.delete("drafts", "id='basic'", null); tick("drafts") }
            else if (saved.isNotEmpty()) putDraft("basic", draft.copy(changes = remaining, expected = draft.expected - saved).json())
        }
        if (changed) tick("profile"); Unit
    }
    fun count(kind: HealthBackgroundKind): Long = db.rawQuery("SELECT COUNT(*) FROM entries WHERE kind=?", arrayOf(kind.name)).use { it.moveToFirst(); it.getLong(0) }
    fun entry(id: String): HealthBackgroundEntry? {
        require(HealthProfilePolicy.uuid(id))
        return db.rawQuery("SELECT kind,token,updated_at,payload FROM entries WHERE id=?", arrayOf(id)).use {
            if (!it.moveToFirst()) null else {
                val kind = it.getString(0); val token = it.getString(1); val time = it.getLong(2)
                HealthBackgroundEntry.from(unpack("entry", "$id:$kind:$token", it.getBlob(3))).also { value ->
                    check(value.id == id && value.kind.name == kind && value.token == token && value.updatedAt == time && HealthProfilePolicy.entry(value) == value)
                }
            }
        }
    }
    fun page(kind: HealthBackgroundKind, after: HealthBackgroundCursor? = null): HealthBackgroundPage = transaction {
        val version = clock("category:${kind.name}")
        if (after != null && (after.kind != kind || after.version != version)) throw HealthProfileConflict()
        val args = arrayListOf(kind.name); val where = if (after == null) "" else {
            args += listOf(after.updatedAt.toString(), after.updatedAt.toString(), after.id); " AND (updated_at<? OR (updated_at=? AND id<?))"
        }
        val entries = db.rawQuery("SELECT id FROM entries WHERE kind=?$where ORDER BY updated_at DESC,id DESC LIMIT 31", args.toTypedArray()).use { rows -> buildList {
            while (rows.moveToNext()) add(requireNotNull(entry(rows.getString(0))).also { check(it.kind == kind) })
        } }
        val visible = entries.take(30)
        HealthBackgroundPage(visible, if (entries.size > 30) visible.last().let { HealthBackgroundCursor(kind, it.updatedAt, it.id, version) } else null,
            HealthProfileStamp(generation(), mapOf("category:${kind.name}" to version)))
    }
    fun entryDraft(key: String): HealthBackgroundDraft? {
        require(key.matches(Regex("new:(HISTORY|MEDICATION|ALLERGY)|edit:[0-9a-f-]{36}")))
        return readDraft(key)?.let(HealthBackgroundDraft::from)?.also { check(it.key == key); HealthProfilePolicy.validateDraft(it) }
    }
    fun newEntry(kind: HealthBackgroundKind): HealthBackgroundDraft = transaction { entryDraft("new:${kind.name}") ?: HealthBackgroundDraft(generation(), HealthBackgroundEntry(UUID.randomUUID().toString(), kind, "")) }
    fun editEntry(id: String): HealthBackgroundDraft = transaction {
        entryDraft("edit:$id") ?: (entry(id) ?: throw HealthProfileConflict()).let { HealthBackgroundDraft(generation(), it, it.token) }
    }
    private fun checkDraft(value: HealthBackgroundDraft) {
        requireGeneration(value.generation); HealthProfilePolicy.validateDraft(value)
        val prior = entry(value.entry.id)
        if ((prior?.token ?: "") != value.expected || prior != null && prior.kind != value.entry.kind) throw HealthProfileConflict()
    }
    fun draft(value: HealthBackgroundDraft) = transaction(true) { checkDraft(value); putDraft(value.key, value.json()) }
    fun discardEntry(value: HealthBackgroundDraft) = transaction(true) { requireGeneration(value.generation); db.delete("drafts", "id=?", arrayOf(value.key)); tick("drafts") }
    fun saveEntry(value: HealthBackgroundDraft): HealthBackgroundEntry = transaction(true) {
        checkDraft(value); val entry = HealthProfilePolicy.entry(value.entry).copy(token = UUID.randomUUID().toString(), updatedAt = System.currentTimeMillis())
        db.insertWithOnConflict("entries", null, ContentValues().apply {
            put("id", entry.id); put("kind", entry.kind.name); put("token", entry.token); put("updated_at", entry.updatedAt)
            put("payload", pack("entry", "${entry.id}:${entry.kind.name}:${entry.token}", entry.json()))
        }, SQLiteDatabase.CONFLICT_REPLACE)
        if (entryDraft(value.key) == value) { db.delete("drafts", "id=?", arrayOf(value.key)); tick("drafts") }
        tick("category:${entry.kind.name}"); tick("profile"); entry
    }
    fun deleteEntry(id: String, token: String, generation: String) = transaction(true) {
        requireGeneration(generation); val entry = entry(id) ?: throw HealthProfileConflict()
        if (entry.token != token) throw HealthProfileConflict()
        db.delete("entries", "id=?", arrayOf(id)); db.delete("drafts", "id=?", arrayOf("edit:$id")); tick("drafts"); tick("category:${entry.kind.name}"); tick("profile"); Unit
    }
    fun capture(fields: Set<HealthProfileField>, entryIds: Set<String>): HealthProfileContext = HealthPrivacyStore.track(context,
        HealthAccessScope(HealthAccessPurpose.PROFILE_CONTEXT, fields = fields, count = entryIds.size.toLong()), privacyDatabase) { transaction {
        val selected = fields.associateWith(::cell); val entries = entryIds.sorted().map { requireNotNull(entry(it)) }
        HealthProfileContext(selected.mapValues { it.value.value }, entries, HealthProfileStamp(generation(),
            selected.mapKeys { "field:${it.key.name}" }.mapValues { it.value.token } + entries.associate { "entry:${it.id}" to it.token }))
    } }
    fun isCurrent(stamp: HealthProfileStamp): Boolean = transaction {
        generation() == stamp.generation && stamp.versions.all { (key, token) ->
            when {
                key.startsWith("field:") -> clock("field:${HealthProfileField.valueOf(key.removePrefix("field:")).name}") == token
                key.startsWith("category:") -> clock("category:${HealthBackgroundKind.valueOf(key.removePrefix("category:")).name}") == token
                key.startsWith("entry:") -> entry(key.removePrefix("entry:"))?.token == token
                else -> error("Invalid health profile dependency")
            }
        }
    }
    fun deletePreview(): HealthProfileDeletePreview = transaction {
        val fields = HealthProfileField.entries.count { cell(it).value != null }
        val entries = HealthBackgroundKind.entries.sumOf(::count)
        val drafts = db.rawQuery("SELECT COUNT(*) FROM drafts", null).use { it.moveToFirst(); it.getLong(0) }
        HealthProfileDeletePreview(fields, entries, drafts, clock("profile") + "|" + generation() + "|" + clock("drafts"))
    }
    fun clear(preview: HealthProfileDeletePreview) = transaction(true) {
        if (preview != deletePreview()) throw HealthProfileConflict()
        db.delete("basics", null, null); db.delete("entries", null, null); db.delete("drafts", null, null); db.delete("clocks", null, null)
        tick("generation"); tick("profile"); Unit
    }
    override fun close() = helper.close()
    private class Database(context: Context, name: String) : SQLiteOpenHelper(context, name, null, 1) {
        init { setWriteAheadLoggingEnabled(true) }
        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE clocks(key TEXT PRIMARY KEY,token TEXT NOT NULL,payload BLOB NOT NULL)")
            db.execSQL("CREATE TABLE basics(field TEXT PRIMARY KEY,token TEXT NOT NULL,updated_at INTEGER NOT NULL,payload BLOB NOT NULL)")
            db.execSQL("CREATE TABLE entries(id TEXT PRIMARY KEY,kind TEXT NOT NULL,token TEXT NOT NULL,updated_at INTEGER NOT NULL,payload BLOB NOT NULL)")
            db.execSQL("CREATE INDEX background_pages ON entries(kind,updated_at DESC,id DESC)")
            db.execSQL("CREATE TABLE drafts(id TEXT PRIMARY KEY,payload BLOB NOT NULL)")
        }
        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) { error("Unsupported health-profile upgrade") }
    }
    companion object {
        const val DEFAULT_DB = "health_profiles_v1.db"
        fun changes(context: Context, name: String = DEFAULT_DB) = android.net.Uri.parse("content://${context.packageName}.health-originals/changes/profiles/" + android.net.Uri.encode(name))
    }
}
