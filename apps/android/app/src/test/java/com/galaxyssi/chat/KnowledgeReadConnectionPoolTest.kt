package com.galaxyssi.chat

import java.io.Closeable
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.*
import org.junit.Test

class KnowledgeReadConnectionPoolTest {
    private class Resource(val key: String, val closing: () -> Unit = {}) : Closeable {
        val closes = AtomicInteger()
        override fun close() { closes.incrementAndGet(); closing() }
    }

    @Test fun reuseHasFixedCapacityAndDoesNotReopen() = KnowledgeReadConnectionPool<String, Resource>(2).use { pool ->
        repeat(100) { assertEquals("a", pool.read("a", create = { Resource("a") }) { it.key }) }
        assertEquals(1L, pool.stats().opened); assertEquals(99L, pool.stats().reused)
        assertEquals(1, pool.stats().idle); assertEquals(0, pool.stats().active)
    }

    @Test fun idleEvictionIsLeastRecentlyUsed() = KnowledgeReadConnectionPool<String, Resource>(2).use { pool ->
        val a = Resource("a"); val b = Resource("b")
        pool.borrow("a") { a }.close(); pool.borrow("b") { b }.close()
        pool.borrow("a") { error("must reuse a") }.close()
        pool.borrow("c") { Resource("c") }.close()
        assertEquals(0, a.closes.get()); assertEquals(1, b.closes.get())
        assertEquals(2, pool.stats().peak)
    }

    @Test fun invalidIdentityReopensWithoutReturningStaleResource() = KnowledgeReadConnectionPool<String, Resource>(1).use { pool ->
        val old = Resource("old")
        pool.borrow("a") { old }.close()
        pool.borrow("a", valid = { false }) { Resource("new") }.use { assertEquals("new", it.value.key) }
        assertEquals(1, old.closes.get()); assertEquals(2L, pool.stats().opened)
    }

    @Test fun factoryFailureReturnsReservedCapacity() = KnowledgeReadConnectionPool<String, Resource>(1).use { pool ->
        assertThrows(IllegalStateException::class.java) { pool.borrow("a") { error("open failed") } }
        assertEquals(0, pool.stats().active)
        pool.borrow("b") { Resource("b") }.close()
        assertEquals(1, pool.stats().idle)
    }

    @Test fun failedReadDiscardsConnectionAndLeaseClosesOnce() = KnowledgeReadConnectionPool<String, Resource>(1).use { pool ->
        val first = Resource("a")
        assertThrows(IllegalStateException::class.java) { pool.read("a", create = { first }) { error("read failed") } }
        assertEquals(1, first.closes.get())
        val lease = pool.borrow("a") { Resource("a") }
        lease.close(); lease.close()
        assertThrows(IllegalStateException::class.java) { lease.value }
        assertEquals(2L, pool.stats().opened)
    }

    @Test fun fullPoolWaitsWithoutOpeningAnExtraConnection() = KnowledgeReadConnectionPool<String, Resource>(1).use { pool ->
        val held = pool.borrow("a") { Resource("a") }
        val executor = Executors.newSingleThreadExecutor()
        val started = CountDownLatch(1)
        val opened = AtomicInteger()
        try {
            val future = executor.submit<String> {
                started.countDown()
                pool.borrow("b") { opened.incrementAndGet(); Resource("b") }.use { it.value.key }
            }
            assertTrue(started.await(3, TimeUnit.SECONDS))
            assertThrows(TimeoutException::class.java) { future.get(100, TimeUnit.MILLISECONDS) }
            assertEquals(0, opened.get()); held.close()
            assertEquals("b", future.get(3, TimeUnit.SECONDS)); assertEquals(1, pool.stats().peak)
        } finally { held.close(); executor.shutdownNow(); assertTrue(executor.awaitTermination(3, TimeUnit.SECONDS)) }
    }

    @Test fun waitingReaderCanBeInterruptedWithoutLeakingCapacity() = KnowledgeReadConnectionPool<String, Resource>(1).use { pool ->
        pool.borrow("a") { Resource("a") }.use {
            val started = CountDownLatch(1)
            val result = AtomicReference<Throwable>()
            val thread = Thread {
                started.countDown()
                try { pool.borrow("b") { error("must not open") }.close() } catch (error: Throwable) { result.set(error) }
            }
            thread.start(); assertTrue(started.await(3, TimeUnit.SECONDS)); thread.interrupt(); thread.join(3000)
            assertFalse(thread.isAlive); assertTrue(result.get() is InterruptedException)
            assertEquals(1, pool.stats().active)
        }
        assertEquals(1, pool.stats().idle)
    }

    @Test fun strictRetirementRefusesActiveLeaseWithoutInvalidatingIt() = KnowledgeReadConnectionPool<String, Resource>(1).use { pool ->
        val resource = Resource("a")
        pool.borrow("a") { resource }.use {
            assertThrows(IllegalStateException::class.java) { pool.invalidate({ true }, requireIdle = true) }
            assertEquals(0, resource.closes.get())
        }
        pool.borrow("a") { error("lease should remain reusable") }.close()
        pool.invalidate({ true }, requireIdle = true)
        assertEquals(1, resource.closes.get())
    }

    @Test fun shutdownDefersActiveCloseAndRejectsNewReaders() {
        val pool = KnowledgeReadConnectionPool<String, Resource>(1)
        val resource = Resource("a")
        val held = pool.borrow("a") { resource }
        pool.close(); assertEquals(0, resource.closes.get())
        assertThrows(IllegalStateException::class.java) { pool.borrow("b") { Resource("b") } }
        held.close(); pool.close(); assertEquals(1, resource.closes.get())
    }

    @Test fun ownerInvalidationDiscardsBusyResourceOnlyAfterRelease() = KnowledgeReadConnectionPool<String, Resource>(2).use { pool ->
        val a = Resource("a"); val b = Resource("b")
        pool.borrow("b") { b }.close()
        pool.borrow("a") { a }.use {
            pool.invalidate({ it == "a" })
            assertEquals(0, a.closes.get()); assertEquals(0, b.closes.get())
        }
        assertEquals(1, a.closes.get())
        pool.borrow("b") { error("unrelated entry must remain") }.close()
    }

    @Test fun closingDuringFactoryDoesNotLeakOrPublishTheOpenedResource() {
        val pool = KnowledgeReadConnectionPool<String, Resource>(1)
        val opening = CountDownLatch(1); val proceed = CountDownLatch(1)
        val resource = Resource("a")
        val result = AtomicReference<Throwable>()
        val thread = Thread {
            try { pool.borrow("a") { opening.countDown(); check(proceed.await(3, TimeUnit.SECONDS)); resource }.close() }
            catch (error: Throwable) { result.set(error) }
        }
        thread.start(); assertTrue(opening.await(3, TimeUnit.SECONDS)); pool.close(); proceed.countDown(); thread.join(3000)
        assertFalse(thread.isAlive); assertTrue(result.get() is IllegalStateException)
        assertEquals(1, resource.closes.get()); assertEquals(0, pool.stats().active)
    }

    @Test fun failingOneCloseDoesNotSkipOtherResources() {
        val pool = KnowledgeReadConnectionPool<String, Resource>(2)
        val a = Resource("a") { error("close failure") }; val b = Resource("b")
        pool.borrow("a") { a }.close(); pool.borrow("b") { b }.close()
        assertThrows(IllegalStateException::class.java) { pool.close() }
        assertEquals(1, a.closes.get()); assertEquals(1, b.closes.get())
        assertEquals(0, pool.stats().active); assertEquals(0, pool.stats().idle)
    }

    @Test fun closingResourceStillCountsAgainstCapacity() = KnowledgeReadConnectionPool<String, Resource>(1).use { pool ->
        val closing = CountDownLatch(1); val proceed = CountDownLatch(1)
        val resource = Resource("a") { closing.countDown(); check(proceed.await(3, TimeUnit.SECONDS)) }
        pool.borrow("a") { resource }.close()
        val executor = Executors.newFixedThreadPool(2)
        val opened = AtomicInteger()
        try {
            val trim = executor.submit { pool.invalidate({ true }) }
            assertTrue(closing.await(3, TimeUnit.SECONDS))
            val next = executor.submit { pool.borrow("b") { opened.incrementAndGet(); Resource("b") }.close() }
            assertThrows(TimeoutException::class.java) { next.get(100, TimeUnit.MILLISECONDS) }
            assertEquals(0, opened.get()); proceed.countDown()
            trim.get(3, TimeUnit.SECONDS); next.get(3, TimeUnit.SECONDS)
            assertEquals(1, pool.stats().peak)
        } finally { proceed.countDown(); executor.shutdownNow(); assertTrue(executor.awaitTermination(3, TimeUnit.SECONDS)) }
    }
}
