package com.galaxyssi.chat

import android.os.Process
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Invoked as three separate instrumentation processes; the first intentionally dies. */
@RunWith(AndroidJUnit4::class)
class KnowledgeEnrollmentRecoveryDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val name get() = InstrumentationRegistry.getArguments().getString("enrollmentFixture").orEmpty().also {
        org.junit.Assume.assumeTrue("Explicit isolated recovery fixture required", it.isNotEmpty())
        require(it.matches(Regex("test-enrollment-recovery-[a-f0-9]{24}\\.db")))
    }
    private val legacy get() = "legacy-$name"
    private val spec = KnowledgeVectorSpec("a".repeat(64), 4, 32)
    @Test fun prepareAndTerminate() {
        check(!context.getDatabasePath(name).exists()) { "Recovery fixture already exists" }
        val store = SQLiteAgentKnowledgeStore(context, name, legacy) { _, _ -> }
        store.replaceSource("recovery", (1..131).map {
            AgentKnowledgeItem("recovery-$it", AgentKnowledgeKind.NOTE, "Recovery $it", "\u91cd\u542f\u6062\u590d-$it", source = "recovery")
        })
        val db = AgentKnowledgeDatabase.shared(context, name, legacy)
        val ledger = db.vectors(spec)
        ledger.ensureRegistered()
        db.transaction { KnowledgeVectorEnrollment.refill(it, ledger.modelKey) }
        println("KNOWLEDGE_ENROLLMENT_RECOVERY committed_page=64 pid=${Process.myPid()}")
        System.out.flush()
        Process.killProcess(Process.myPid())
        error("Intentional process termination did not occur")
    }
    @Test fun verifyAfterRestart() {
        check(context.getDatabasePath(name).exists()) { "Missing committed recovery fixture" }
        val db = AgentKnowledgeDatabase.shared(context, name, legacy)
        val ledger = db.vectors(spec)
        val keys = (1..131).map { db.key("id", "recovery-$it") }.sorted()
        db.access { sql ->
            val checkpoint = KnowledgeVectorEnrollment.state(sql, ledger.modelKey)
            assertEquals(keys[63], checkpoint.after); assertFalse(checkpoint.complete)
            sql.rawQuery("SELECT count(*) FROM knowledge_vector_queue", null).use {
                assertTrue(it.moveToFirst()); assertEquals(64L, it.getLong(0))
            }
        }
        db.transaction { KnowledgeVectorEnrollment.refill(it, ledger.modelKey) }
        db.transaction { assertTrue(KnowledgeVectorEnrollment.refill(it, ledger.modelKey).complete) }
        db.access { sql -> sql.rawQuery("SELECT item_key FROM knowledge_vector_queue ORDER BY item_key", null).use { cursor ->
            keys.forEach { assertTrue(cursor.moveToNext()); assertEquals(it, cursor.getString(0)) }
            assertFalse(cursor.moveToNext())
        } }
        val store = SQLiteAgentKnowledgeStore(context, name, legacy) { _, _ -> }
        assertEquals(131, store.stats().itemCount)
        db.access { sql -> (1..131).forEach {
            assertEquals("\u91cd\u542f\u6062\u590d-$it", requireNotNull(db.read(sql, db.key("id", "recovery-$it"))).content)
        } }
        store.close()
        println("KNOWLEDGE_ENROLLMENT_RECOVERY resumed=131 exact_sources=131 pid=${Process.myPid()}")
    }
    @Test fun cleanup() {
        AgentKnowledgeDatabase.release(context, name)
        context.deleteDatabase(name)
        AgentEncryptedPreferences(context, legacy).clear()
    }
}
