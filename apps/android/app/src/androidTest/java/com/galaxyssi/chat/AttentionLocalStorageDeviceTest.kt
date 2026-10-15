package com.galaxyssi.chat

import android.content.ContentValues
import android.content.Context
import android.content.ContextWrapper
import android.database.DatabaseErrorHandler
import android.database.sqlite.SQLiteDatabase
import android.os.Bundle
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import java.io.File
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AttentionLocalStorageDeviceTest {
    private val context = IsolatedContext(InstrumentationRegistry.getInstrumentation().targetContext)

    @After fun cleanup() { context.cleanup() }

    @Test fun legacyDiscoveryRowsMigrateWithoutLosingContent() {
        val name = "attention_titles_v1"
        val db = AgentEncryptedDatabase(context, name)
        val key = "synthetic-storage-${UUID.randomUUID()}"
        val value = """{"title":"Public news","translated":"Translation","version":1}"""
        val encrypted = AgentStorageCipher.encrypt(value, "database:$name:$key".toByteArray())
        try {
            db.indexedTransaction { sql -> sql.insertOrThrow("encrypted_values", null, ContentValues().apply {
                put("storage_key", key); put("encrypted_value", encrypted)
            }) }
            assertEquals(value, db.readString(key, ""))
            assertEquals(AttentionLocalStoragePolicy.PREFIX + value, raw(db, key))
            assertEquals(value, AgentEncryptedDatabase(context, name).readString(key, ""))
            db.writeString(key, "updated")
            assertEquals(AttentionLocalStoragePolicy.PREFIX + "updated", raw(db, key))
        } finally { db.remove(key) }
    }

    @Test fun publicNewsAndPersonalInsightsKeepSeparateStoragePolicies() {
        val name = GlobalAgentRepository.DATABASE_NAME
        val db = AgentEncryptedDatabase(context, name)
        val key = "proactive_message_row:synthetic-storage-${UUID.randomUUID()}"
        val id = key.removePrefix("proactive_message_row:")
        val personal = """{"id":"$id","status":"DISMISSED","source_event_id":"private-conversation","content":"Personal insight"}"""
        val news = """{"id":"$id","status":"DISMISSED","source_event_id":"research:attention-research:ai:example","content":"Public news"}"""
        try {
            db.writeString(key, personal)
            assertFalse(raw(db, key).startsWith(AttentionLocalStoragePolicy.PREFIX))
            assertEquals(personal, db.readString(key, ""))
            db.writeString(key, news)
            assertEquals(AttentionLocalStoragePolicy.PREFIX + news, raw(db, key))
            db.writeString(key, personal)
            assertFalse(raw(db, key).startsWith(AttentionLocalStoragePolicy.PREFIX))
            assertEquals(personal, db.readString(key, ""))
        } finally { db.remove(key) }
    }

    @Test fun countsUseOnlyIndexAndMatchGroupedUnreadSemantics() {
        val db = AgentEncryptedDatabase(context, "synthetic-attention-counts-${UUID.randomUUID()}")
        val index = ProactiveMessageReadIndex(db)
        try {
            val records = listOf(record("a"), record("b", viewed = 3), record("c", "digest"),
                record("d", "digest", 3), record("e", "hidden"), record("f", "hidden"),
                record("g"), record("pending").put("status", "PENDING"))
            index.prepare { records.asSequence() }
            assertEquals(ProactiveInboxCounts(5, 4), index.counts(emptyList()))
            val feedback = listOf(feedback("f", GlobalAgentFeedbackKind.NOT_RELEVANT),
                feedback("g", GlobalAgentFeedbackKind.HELPFUL))
            assertEquals(ProactiveInboxCounts(4, 2), index.counts(feedback))
            db.indexedTransaction { sql -> index.update(sql, ProactiveMessageReadIndex.ROW_PREFIX + "c",
                record("c", "digest", 9).toString()) }
            assertEquals(ProactiveInboxCounts(4, 1), index.counts(feedback))
        } finally { db.clear() }
    }

    @Test fun tenThousandNewsCountsDoNotReadOrDecryptBodies() {
        val db = AgentEncryptedDatabase(context, "synthetic-attention-large-${UUID.randomUUID()}")
        val index = ProactiveMessageReadIndex(db)
        try {
            index.prepare { (0 until 10_000).asSequence().map { record(it.toString(), viewed = if (it % 2 == 0) 1 else 0) } }
            // No encrypted body rows exist: counting must work entirely from the index.
            val start = SystemClock.elapsedRealtime()
            assertEquals(ProactiveInboxCounts(10_000, 5_000), index.counts(emptyList()))
            val elapsed = SystemClock.elapsedRealtime() - start
            InstrumentationRegistry.getInstrumentation().sendStatus(0, Bundle().apply {
                putString("stream", "indexed_10000_count_ms=$elapsed\n")
            })
            assertTrue("Lightweight counting unexpectedly stalled: $elapsed ms", elapsed < 1_000)
        } finally { db.clear() }
    }

    private fun record(id: String, digest: String = "", viewed: Long = 0) = JSONObject()
        .put("id", id).put("status", "DELIVERED").put("target", "GLOBAL_DIGEST")
        .put("delivery_group_id", digest).put("viewed_at_millis", viewed)

    private fun feedback(id: String, kind: GlobalAgentFeedbackKind) = GlobalAgentFeedback(
        proactiveMessageId = id, deliveryGroupId = "", conversationId = "", topic = "",
        target = GlobalProactiveTarget.GLOBAL_DIGEST, kind = kind)

    private fun raw(db: AgentEncryptedDatabase, key: String): String = db.indexedTransaction { sql ->
        sql.rawQuery("SELECT encrypted_value FROM encrypted_values WHERE storage_key = ?", arrayOf(key)).use {
            check(it.moveToFirst()); it.getString(0)
        }
    }

    private class IsolatedContext(base: Context) : ContextWrapper(base) {
        private val prefix = "attention-storage-test-${UUID.randomUUID()}-"
        private val names = mutableSetOf<String>()
        override fun getApplicationContext(): Context = this
        override fun getDatabasePath(name: String): File = if (File(name).isAbsolute) File(name) else {
            names.add(prefix + name); baseContext.getDatabasePath(prefix + name)
        }
        override fun openOrCreateDatabase(name: String, mode: Int, factory: SQLiteDatabase.CursorFactory?): SQLiteDatabase =
            baseContext.openOrCreateDatabase(getDatabasePath(name).absolutePath, mode, factory)
        override fun openOrCreateDatabase(name: String, mode: Int, factory: SQLiteDatabase.CursorFactory?, handler: DatabaseErrorHandler?): SQLiteDatabase =
            baseContext.openOrCreateDatabase(getDatabasePath(name).absolutePath, mode, factory, handler)
        fun cleanup() { names.forEach(baseContext::deleteDatabase) }
    }
}
