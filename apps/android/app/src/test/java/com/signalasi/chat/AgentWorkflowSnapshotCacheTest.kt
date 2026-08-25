package com.signalasi.chat

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

class AgentWorkflowSnapshotCacheTest {
    @Test
    fun sameRawContentReusesDecodedSnapshot() {
        val cache = AgentWorkflowSnapshotCache()
        val decodes = AtomicInteger()
        val decode: (String) -> List<AgentWorkflow> = {
            decodes.incrementAndGet()
            listOf(workflow(it))
        }

        val first = cache.get("first", decode)
        val second = cache.get("first", decode)

        assertSame(first, second)
        assertEquals(1, decodes.get())
    }

    @Test
    fun changedRawContentRefreshesSnapshot() {
        val cache = AgentWorkflowSnapshotCache()
        val decodes = AtomicInteger()
        val decode: (String) -> List<AgentWorkflow> = {
            decodes.incrementAndGet()
            listOf(workflow(it))
        }

        cache.get("first", decode)
        val second = cache.get("second", decode)

        assertEquals("second", second.single().name)
        assertEquals(2, decodes.get())
    }

    @Test
    fun successfulWritePrimesSnapshotWithoutAnotherDecode() {
        val cache = AgentWorkflowSnapshotCache()
        val written = listOf(workflow("written"))
        cache.put("encoded", written)

        val result = cache.get("encoded") { error("write-through snapshot should be reused") }

        assertEquals(written, result)
    }

    @Test
    fun concurrentReadersDecodeOneSnapshotOnce() {
        val cache = AgentWorkflowSnapshotCache()
        val decodes = AtomicInteger()
        val ready = CountDownLatch(8)
        val start = CountDownLatch(1)
        val executor = Executors.newFixedThreadPool(8)
        val futures = (1..8).map {
            executor.submit<List<AgentWorkflow>> {
                ready.countDown()
                start.await(2, TimeUnit.SECONDS)
                cache.get("shared") { raw ->
                    decodes.incrementAndGet()
                    Thread.sleep(10)
                    listOf(workflow(raw))
                }
            }
        }

        check(ready.await(2, TimeUnit.SECONDS))
        start.countDown()
        val snapshots = futures.map { it.get(2, TimeUnit.SECONDS) }
        executor.shutdownNow()

        snapshots.drop(1).forEach { assertSame(snapshots.first(), it) }
        assertEquals(1, decodes.get())
    }

    private fun workflow(name: String) = AgentWorkflow(name = name, goal = "run $name")
}
