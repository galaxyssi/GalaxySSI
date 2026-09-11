package com.galaxyssi.chat

import android.os.Process
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/** Separate explicit invocations prove SQLite rollback after actual process death. */
@RunWith(AndroidJUnit4::class)
class KnowledgeBackupRecoveryDeviceTest {
    private val name get() = InstrumentationRegistry.getArguments().getString("knowledgeRecoveryFixture").orEmpty().also {
        assumeTrue("Explicit isolated recovery fixture required", it.isNotEmpty())
        require(it.matches(Regex("test-knowledge-backup-recovery-[a-f0-9]{24}\\.db")))
    }
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    @Test fun prepareAndTerminateDuringRestore() {
        check(!context.getDatabasePath(name).exists())
        KnowledgeBackupTestFixture(name).use { f ->
            f.seed(3)
            f.staged((10..20).asSequence().map { f.item(it) }) { stage ->
                File(context.cacheDir, "$name.stage").writeText(stage.file.name)
                f.store.restoreRecords(stage) { written -> if (written == 2L) {
                    println("KNOWLEDGE_BACKUP_RECOVERY before=3 uncommitted=2 pid=${Process.myPid()}")
                    System.out.flush(); Process.killProcess(Process.myPid())
                    error("Intentional process termination did not occur")
                } }
            }
        }
    }
    @Test fun verifyAfterRestart() {
        check(context.getDatabasePath(name).exists())
        KnowledgeBackupTestFixture(name).use { f ->
            assertEquals((1..3).map { f.item(it) }.toSet(), f.store.list(20).toSet())
            assertTrue(f.store.findByIds(setOf(f.item(10).id, f.item(11).id)).isEmpty())
            assertFalse(f.store.search("\u77e5\u8bc6", 8).isEmpty())
            f.staged((10..20).asSequence().map { f.item(it) }) { f.store.restoreRecords(it) }
            f.reopen(); assertEquals((10..20).map { f.item(it) }.toSet(), f.store.list(20).toSet())
            f.retain = true
            println("KNOWLEDGE_BACKUP_RECOVERY original=3 rolled_back=2 verified_after_retry=11 pid=${Process.myPid()}")
        }
    }
    @Test fun cleanup() {
        check(context.getDatabasePath(name).exists())
        KnowledgeBackupTestFixture(name).close()
        val marker = File(context.cacheDir, "$name.stage")
        val basename = marker.readText()
        check(basename.matches(Regex("[a-f0-9-]{36}\\.db")))
        val directory = File(context.cacheDir, "knowledge-backup-staging").canonicalFile
        val target = File(directory, basename).canonicalFile
        check(target.parentFile == directory)
        android.database.sqlite.SQLiteDatabase.deleteDatabase(target)
        marker.delete()
    }
}
