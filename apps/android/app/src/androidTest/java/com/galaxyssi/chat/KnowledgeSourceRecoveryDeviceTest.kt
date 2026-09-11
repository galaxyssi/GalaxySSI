package com.galaxyssi.chat

import android.os.Process
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/** Explicit process death between migration pages, followed by a separate instrumentation process. */
@RunWith(AndroidJUnit4::class)
class KnowledgeSourceRecoveryDeviceTest {
    private val name get() = InstrumentationRegistry.getArguments().getString("knowledgeSourceRecoveryFixture").orEmpty().also {
        assumeTrue("Explicit isolated recovery fixture required", it.isNotEmpty())
        require(it.matches(Regex("test-knowledge-backup-source-recovery-[a-f0-9]{24}\\.db")))
    }
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val marker get() = File(context.cacheDir, "$name.source-recovery")

    @Test fun prepareCheckpointAndTerminate() {
        check(!context.getDatabasePath(name).exists())
        KnowledgeBackupTestFixture(name).apply { retain = true }.use { f ->
            f.seed(137); f.store.close()
            val hash = KnowledgeSourceMigrationTestSupport.fingerprint(name)
            val state = KnowledgeSourceMigrationTestSupport.raw(name) { db ->
                db.execSQL("PRAGMA foreign_keys=ON"); db.execSQL("PRAGMA recursive_triggers=ON")
                db.beginTransaction()
                try {
                    KnowledgeSourceDirectoryFixtureSchema.remove(db)
                    KnowledgeSourceDirectorySchema.create(db)
                    assertFalse(KnowledgeSourceDirectory.advance(db))
                    db.setTransactionSuccessful()
                } finally { db.endTransaction() }
                KnowledgeSourceDirectory.state(db)
            }
            assertEquals(64L, state.items)
            marker.writeText(JSONObject().put("pid", Process.myPid()).put("after", state.after).put("sha256", hash).toString())
            println("KNOWLEDGE_SOURCE_RECOVERY committed=64 total=137 pid=${Process.myPid()}")
            System.out.flush(); Process.killProcess(Process.myPid())
            error("Intentional process termination did not occur")
        }
    }

    @Test fun verifyNextProcessResumesWithoutRewritingSourceCiphertext() {
        val saved = JSONObject(marker.readText())
        assertNotEquals(saved.getInt("pid"), Process.myPid())
        val state = KnowledgeSourceMigrationTestSupport.raw(name, KnowledgeSourceDirectory::state)
        assertFalse(state.complete); assertEquals(64L, state.items); assertEquals(saved.getString("after"), state.after)
        KnowledgeBackupTestFixture(name).apply { retain = true }.use { f ->
            KnowledgeSourceMigrationTestSupport.awaitReady(f)
            assertEquals(137, f.store.sourceCount())
            assertEquals(saved.getString("sha256"), KnowledgeSourceMigrationTestSupport.fingerprint(name))
            f.db.backupSnapshot().use { snapshot ->
                var verified = 0
                snapshot.items().forEach { item -> assertEquals(f.item(item.id.removePrefix("backup-").toInt()), item); verified++ }
                assertEquals(137, verified)
            }
            println("KNOWLEDGE_SOURCE_RECOVERY resumed=64 verified=137 old_pid=${saved.getInt("pid")} pid=${Process.myPid()}")
        }
    }

    @Test fun cleanup() {
        check(marker.exists()); check(context.getDatabasePath(name).exists())
        KnowledgeBackupTestFixture(name).close(); check(marker.delete())
    }
}
