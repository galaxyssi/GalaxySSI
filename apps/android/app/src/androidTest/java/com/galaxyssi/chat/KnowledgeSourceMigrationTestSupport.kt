package com.galaxyssi.chat

import androidx.test.platform.app.InstrumentationRegistry
import java.nio.ByteBuffer
import java.security.MessageDigest
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Fixture-only schema changes and streaming ciphertext checks; never opens the production database. */
internal object KnowledgeSourceMigrationTestSupport {
    fun <T> raw(name: String, action: (KnowledgeSqlite) -> T): T {
        require(name.matches(Regex("test-knowledge-backup-[a-z0-9-]+\\.db")))
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val path = context.getDatabasePath(name)
        check(path.exists()) { "Retained encrypted fixture does not exist" }
        return KnowledgeSqlite(path.absolutePath).use(action)
    }

    fun versionSeven(f: KnowledgeBackupTestFixture) {
        f.store.close()
        raw(f.name) { db ->
            db.beginTransaction()
            try {
                KnowledgeSourceDirectoryFixtureSchema.remove(db)
                db.execSQL("PRAGMA user_version=7")
                db.setTransactionSuccessful()
            } finally { db.endTransaction() }
        }
        f.reopen()
    }

    fun fingerprint(name: String): String = raw(name) { db ->
        val digest = MessageDigest.getInstance("SHA-256")
        fun field(value: String) {
            val bytes = value.toByteArray()
            try {
                digest.update(ByteBuffer.allocate(4).putInt(bytes.size).array())
                digest.update(bytes)
            } finally { bytes.fill(0) }
        }
        for ((sql, columns) in listOf(
            "SELECT item_key,title_key,source_key,CAST(updated AS TEXT),header FROM knowledge_items ORDER BY item_key" to 5,
            "SELECT item_key,CAST(ordinal AS TEXT),ciphertext FROM knowledge_chunks ORDER BY item_key,ordinal" to 3
        )) {
            field(sql)
            db.rawQuery(sql, null).use { rows ->
                while (rows.moveToNext()) for (column in 0 until columns) field(rows.getString(column))
            }
        }
        digest.digest().joinToString("") { "%02x".format(it) }
    }

    fun awaitReady(f: KnowledgeBackupTestFixture) {
        val ready = CountDownLatch(1)
        f.store.observeSourceDirectory { ready.countDown() }.use {
            f.db.access { }
            check(ready.await(120, TimeUnit.SECONDS)) { "Source migration did not complete in the test window" }
        }
        check(f.db.sourceMaintenance.failure == null) { f.db.sourceMaintenance.failure.orEmpty() }
        f.db.access { KnowledgeSourceDirectory.state(it).requireReady() }
    }

    fun assertGroup(group: AgentKnowledgeSourceGroup, index: Int) {
        org.junit.Assert.assertEquals("fixture-$index", group.source)
        org.junit.Assert.assertEquals("\u8d44\u6599-$index", group.title)
        org.junit.Assert.assertEquals(index.toLong() + 1, group.updatedAtMillis)
        org.junit.Assert.assertEquals(1, group.chunkCount)
        org.junit.Assert.assertEquals(AgentKnowledgeCloudAccess.DENY, group.cloudAccess)
        org.junit.Assert.assertEquals(AgentKnowledgeAgentAccess.LOCAL_ONLY, group.agentAccess)
        org.junit.Assert.assertTrue(group.allowedAgentIds.isEmpty())
        org.junit.Assert.assertTrue(group.itemIds.isEmpty())
        org.junit.Assert.assertEquals(AgentKnowledgeSourceReference("fixture-$index"), group.reference)
    }
}
