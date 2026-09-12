package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgeSourcePreparationScaleDeviceTest {
    private class Rollback : RuntimeException()

    @Test fun retainedTenThousandBodiesPrepareWithoutReservingWriter() {
        val name = InstrumentationRegistry.getArguments().getString("retainedKnowledgeFixture")
        assumeTrue("Explicit retained synthetic fixture required", name != null)
        requireNotNull(name)
        require(name.matches(Regex("test-knowledge-source-replace-[a-f0-9-]+\\.db")))
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        check(context.getDatabasePath(name).isFile)
        val db = AgentKnowledgeDatabase.shared(context, name, "legacy-$name")
        val writer = Executors.newSingleThreadExecutor()
        try {
            assertEquals(10_001L, db.access(db::stats).itemCount)
            val original = db.searchSnapshot().use { it.recent(1).single() }
            KnowledgeBackupStaging(context).use { stage ->
                stage.acceptSource(original.source, emptySequence())
                var observed = 0L
                var callbackNanos = 0L
                val started = System.nanoTime()
                KnowledgeSourceReplacement(db, stage, original.source).prepare { count ->
                    assertTrue(count > observed && count - observed <= 64)
                    observed = count
                    if (count == 64L) {
                        val callbackStarted = System.nanoTime()
                        writer.submit {
                            repeat(20) { i ->
                                try { db.transaction { sql ->
                                    db.write(sql, original.copy(summary = "rolled-back-probe-$i"))
                                    throw Rollback()
                                } } catch (_: Rollback) { }
                            }
                        }.get(30, TimeUnit.SECONDS)
                        callbackNanos = System.nanoTime() - callbackStarted
                    }
                }
                val elapsed = System.nanoTime() - started
                assertEquals(10_001L, observed)
                var verified = 0L
                for (item in stage.previous()) {
                    assertEquals(original.source, item.source)
                    assertTrue(item.content.isNotEmpty())
                    verified++
                }
                assertEquals(10_001L, verified)
                // Deliberately do not publish this empty replacement or remove the retained source.
                println("KNOWLEDGE_SOURCE_PREPARE_SCALE rows=$observed verified=$verified elapsed_ns=$elapsed " +
                    "callback_ns=$callbackNanos concurrent_rolled_back_writes=20 published=false")
            }
            assertEquals(10_001L, db.access(db::stats).itemCount)
            assertEquals(original, db.searchSnapshot().use { it.recent(1).single() })
        } finally {
            writer.shutdownNow()
            assertTrue(writer.awaitTermination(10, TimeUnit.SECONDS))
            AgentKnowledgeDatabase.release(context, name)
        }
    }
}
