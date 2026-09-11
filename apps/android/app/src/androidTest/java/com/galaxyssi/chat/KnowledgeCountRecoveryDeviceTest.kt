package com.galaxyssi.chat

import android.os.Process
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Explicitly invoked as separate processes; never targets the production database. */
@RunWith(AndroidJUnit4::class)
class KnowledgeCountRecoveryDeviceTest {
    private val name get() = InstrumentationRegistry.getArguments().getString("countFixture").orEmpty().also {
        org.junit.Assume.assumeTrue("Explicit isolated recovery fixture required", it.isNotEmpty())
        require(it.matches(Regex("test-count-recovery-[a-f0-9]{24}\\.db")))
    }
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    @Test fun prepareAndTerminate() {
        check(!context.getDatabasePath(name).exists())
        val f = KnowledgeCountTestFixture(name = name)
        f.seed(131); f.index()
        (1..17).forEach { f.store.upsert(f.item("pending-$it")) }
        f.downgrade(); f.page(KnowledgeCountSchema.Kind.VECTOR); f.page(KnowledgeCountSchema.Kind.QUEUE)
        assertEquals(KnowledgeCountSnapshot(64, 17, false), f.counts())
        println("KNOWLEDGE_COUNT_RECOVERY committed_vectors=64 committed_queue=17 pid=${Process.myPid()}")
        System.out.flush(); Process.killProcess(Process.myPid())
        error("Intentional process termination did not occur")
    }
    @Test fun verifyAfterRestart() {
        check(context.getDatabasePath(name).exists())
        val f = KnowledgeCountTestFixture(name = name)
        assertEquals(KnowledgeCountSnapshot(64, 17, false), f.counts())
        val keys = (1..131).map { f.db.key("id", "source-$it") }.sorted()
        assertEquals(keys[63], f.db.access { KnowledgeCounts.position(it, KnowledgeCountSchema.Kind.VECTOR).item })
        f.finishCounts(); f.verify()
        assertEquals(KnowledgeCountSnapshot(131, 17, true), f.counts())
        f.db.access { sql -> ((1..131).map { "source-$it" } + (1..17).map { "pending-$it" }).forEach {
            assertEquals(f.item(it).content, requireNotNull(f.db.read(sql, f.db.key("id", it))).content)
        } }
        f.store.close()
        println("KNOWLEDGE_COUNT_RECOVERY verified_vectors=131 verified_queue=17 exact_sources=148 pid=${Process.myPid()}")
    }
    @Test fun cleanup() {
        check(context.getDatabasePath(name).exists())
        KnowledgeCountTestFixture(name = name).close()
    }
}
