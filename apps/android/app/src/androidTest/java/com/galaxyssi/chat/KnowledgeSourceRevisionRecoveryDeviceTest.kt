package com.galaxyssi.chat

import android.os.Process
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Actual process death distinguishes committed source clocks from uncommitted changes. */
@RunWith(AndroidJUnit4::class)
class KnowledgeSourceRevisionRecoveryDeviceTest {
    private val name get() = InstrumentationRegistry.getArguments().getString("sourceRevisionRecoveryFixture").orEmpty().also {
        assumeTrue("Explicit isolated revision recovery fixture required", it.isNotBlank())
        require(it.matches(Regex("test-knowledge-backup-revision-recovery-[a-f0-9]{24}\\.db")))
    }
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val marker get() = File(context.cacheDir, "$name.revision-recovery")
    private val reference = AgentKnowledgeSourceReference("\u6062\u590d\u6d4b\u8bd5")

    @Test fun prepareUncommittedRevisionAndTerminate() {
        check(!context.getDatabasePath(name).exists())
        KnowledgeBackupTestFixture(name).apply { retain = true; observe = false }.use { f ->
            f.db.transaction { db -> (1..65).forEach { f.db.write(db, f.item(it).copy(source = reference.source)) } }
            val token = f.store.sourceExport(reference).revision
            val hash = KnowledgeSourceMigrationTestSupport.fingerprint(name)
            f.db.transaction { db ->
                f.db.write(db, f.item(66).copy(source = reference.source))
                assertNotEquals(token, f.store.sourceExport(reference).revision)
                marker.writeText(JSONObject().put("pid", Process.myPid()).put("sha256", hash).put("revision", token).toString())
                println("SOURCE_REVISION_RECOVERY committed=65 uncommitted=1 pid=${Process.myPid()}")
                System.out.flush(); Process.killProcess(Process.myPid())
                error("Intentional process termination did not occur")
            }
        }
    }

    @Test fun verifyNextProcessRestoresCommittedRevisionAndSnapshot() {
        val saved = JSONObject(marker.readText()); assertNotEquals(saved.getInt("pid"), Process.myPid())
        KnowledgeBackupTestFixture(name).apply { retain = true; observe = false }.use { f ->
            val projection = f.store.sourceExport(reference)
            assertEquals(saved.getString("revision"), projection.revision)
            assertEquals(saved.getString("sha256"), KnowledgeSourceMigrationTestSupport.fingerprint(name))
            val rows = projection.snapshot().use { it.items().map { row -> row.id }.toList() }
            assertEquals((65 downTo 1).map { "backup-$it" }, rows)
            println("SOURCE_REVISION_RECOVERY verified=65 old_pid=${saved.getInt("pid")} pid=${Process.myPid()}")
        }
    }

    @Test fun cleanup() {
        check(marker.exists()); check(context.getDatabasePath(name).exists())
        KnowledgeBackupTestFixture(name).close(); check(marker.delete())
    }
}
