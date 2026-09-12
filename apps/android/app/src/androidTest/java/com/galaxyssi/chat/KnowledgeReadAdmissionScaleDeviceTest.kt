package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgeReadAdmissionScaleDeviceTest {
    private class Rollback : RuntimeException()

    @Test fun retainedTenThousandBodySearchCompletesDuringUncommittedWrite() {
        val name = InstrumentationRegistry.getArguments().getString("retainedKnowledgeFixture")
        assumeTrue("Explicit retained synthetic fixture required", name != null)
        requireNotNull(name)
        require(name.matches(Regex("test-knowledge-source-replace-[a-f0-9-]+\\.db")))
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        check(context.getDatabasePath(name).isFile)
        val db = AgentKnowledgeDatabase.shared(context, name, "legacy-$name")
        val executor = Executors.newFixedThreadPool(2)
        val held = CountDownLatch(1)
        val release = CountDownLatch(1)
        try {
            assertEquals(10_001L, db.access(db::stats).itemCount)
            val original = db.searchSnapshot().use { it.recent(1).single() }
            val writer = executor.submit {
                try { db.transaction { sql ->
                    db.write(sql, original.copy(content = "uncommitted scale probe"))
                    held.countDown(); check(release.await(60, TimeUnit.SECONDS)); throw Rollback()
                } } catch (_: Rollback) { }
            }
            check(held.await(10, TimeUnit.SECONDS))
            val reader = executor.submit {
                val samples = LongArray(100)
                repeat(samples.size) { i ->
                    val started = System.nanoTime()
                    db.searchSnapshot().use { read ->
                        val items = read.recent(8).toList()
                        assertEquals(8, items.size); assertEquals(original, items.first())
                        val hits = items.map { AgentKnowledgeHit(it, 1.0, it.summary, emptyList()) }
                        assertEquals(hits, read.validate(hits))
                    }
                    samples[i] = System.nanoTime() - started
                }
                samples.sort()
                println("KNOWLEDGE_READ_ADMISSION_SCALE rows=10001 samples=100 results=8 " +
                    "p50_ns=${samples[49]} p95_ns=${samples[94]} p99_ns=${samples[98]} " +
                    "over_200ms=${samples.count { it > 200_000_000L }}")
            }
            try { reader.get(30, TimeUnit.SECONDS) } finally {
                release.countDown(); writer.get(10, TimeUnit.SECONDS)
            }
            assertEquals(10_001L, db.access(db::stats).itemCount)
            assertEquals(original, db.searchSnapshot().use { it.recent(1).single() })
        } finally {
            release.countDown(); executor.shutdownNow()
            assertTrue(executor.awaitTermination(10, TimeUnit.SECONDS))
            AgentKnowledgeDatabase.release(context, name)
        }
    }
}
