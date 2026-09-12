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

/** Kills the fixture process with an uncommitted source/preview pair, then verifies another process. */
@RunWith(AndroidJUnit4::class)
class KnowledgeSourcePreviewRecoveryDeviceTest {
    private val name get() = InstrumentationRegistry.getArguments().getString("knowledgePreviewRecoveryFixture").orEmpty().also {
        assumeTrue("Explicit isolated preview recovery fixture required", it.isNotEmpty())
        require(it.matches(Regex("test-knowledge-backup-preview-recovery-[a-f0-9]{24}\\.db")))
    }
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val marker get() = File(context.cacheDir, "$name.preview-recovery")

    @Test fun prepareUncommittedWriteAndTerminate() {
        check(!context.getDatabasePath(name).exists())
        KnowledgeBackupTestFixture(name).apply { retain = true; observe = false }.use { f ->
            f.seed(65)
            assertEquals(65, KnowledgeSourcePreviewFixtureSchema.count(f))
            assertFalse(f.db.hasActivePreviewKey)
            val hash = KnowledgeSourceMigrationTestSupport.fingerprint(name)
            f.db.transaction { db ->
                f.db.write(db, f.item(100))
                assertEquals(66, KnowledgeSourcePreviewFixtureSchema.count(f))
                assertTrue(f.db.hasActivePreviewKey)
                marker.writeText(JSONObject().put("pid", Process.myPid()).put("sha256", hash).toString())
                println("KNOWLEDGE_PREVIEW_RECOVERY committed=65 uncommitted=1 pid=${Process.myPid()}")
                System.out.flush(); Process.killProcess(Process.myPid())
                error("Intentional process termination did not occur")
            }
        }
    }

    @Test fun verifyNextProcessRollsBackAndUsesPersistedPreviews() {
        val saved = JSONObject(marker.readText())
        assertNotEquals(saved.getInt("pid"), Process.myPid())
        KnowledgeBackupTestFixture(name).apply { retain = true; observe = false }.use { f ->
            KnowledgeSourceMigrationTestSupport.awaitReady(f)
            assertEquals(65, f.store.sourceCount())
            assertEquals(65, KnowledgeSourcePreviewFixtureSchema.count(f))
            assertEquals(saved.getString("sha256"), KnowledgeSourceMigrationTestSupport.fingerprint(name))
            val page = f.store.sourcePage(null, 50)
            val last = f.store.sourcePage(requireNotNull(page.next), 50)
            assertNull(last.next)
            (page.groups + last.groups).forEachIndexed { index, group ->
                KnowledgeSourceMigrationTestSupport.assertGroup(group, 65 - index)
            }
            assertEquals(65L, f.db.sourcePreviewHits); assertEquals(0L, f.db.sourcePreviewMisses)
            assertEquals(0L, f.db.decryptedItemReads); assertFalse(f.db.hasActivePreviewKey)
            println("KNOWLEDGE_PREVIEW_RECOVERY verified=65 old_pid=${saved.getInt("pid")} pid=${Process.myPid()}")
        }
    }

    @Test fun cleanup() {
        check(marker.exists()); check(context.getDatabasePath(name).exists())
        KnowledgeBackupTestFixture(name).close(); check(marker.delete())
    }
}
