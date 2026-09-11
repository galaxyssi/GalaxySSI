package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class MemorySegmentAccessProcessTest {
    @get:Rule val temporary = TemporaryFolder()

    @Test fun processDeathReleasesPublicationLockAndUnblocksMaintenance() = probe(false)
    @Test fun processDeathReleasesMaintenanceLockAndUnblocksReaders() = probe(true)

    private fun probe(exclusive: Boolean) {
        val lock = File(temporary.root, "segment.lock")
        val ready = File(temporary.root, "ready")
        val log = File(temporary.root, "child.log")
        val java = File(System.getProperty("java.home"), "bin/java").absolutePath
        val classpath = listOf(MemorySegmentAccess::class.java, MemorySegmentAccessProcessProbe::class.java, kotlin.Unit::class.java)
            .map { File(requireNotNull(requireNotNull(it.protectionDomain).codeSource).location.toURI()).absolutePath }
            .distinct().joinToString(File.pathSeparator)
        val child = ProcessBuilder(java, "-cp", classpath, MemorySegmentAccessProcessProbe::class.java.name,
            lock.absolutePath, ready.absolutePath, exclusive.toString()).redirectErrorStream(true).redirectOutput(log).start()
        val pool = Executors.newSingleThreadExecutor()
        try {
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(15)
            while (!ready.exists() && child.isAlive && System.nanoTime() < deadline) Thread.sleep(10)
            assertTrue("Child did not acquire lock: ${log.readText()}", ready.exists())
            val access = MemorySegmentAccess(lock)
            assertNull(access.tryMaintenance { fail("Child owns the lock"); 1 })
            if (!exclusive) assertEquals(7, access.readWrite { 7 })
            val started = CountDownLatch(1)
            val pending = pool.submit<Int> {
                started.countDown()
                if (exclusive) access.readWrite { 9 } else access.maintenance { 9 }
            }
            assertTrue(started.await(5, TimeUnit.SECONDS))
            Thread.sleep(100)
            assertFalse(pending.isDone)
            child.destroyForcibly()
            assertTrue(child.waitFor(5, TimeUnit.SECONDS))
            assertEquals(9, pending.get(5, TimeUnit.SECONDS).toInt())
            assertEquals(11, access.tryMaintenance { 11 })
        } finally {
            child.destroyForcibly(); child.waitFor(5, TimeUnit.SECONDS)
            pool.shutdownNow(); assertTrue(pool.awaitTermination(5, TimeUnit.SECONDS))
        }
    }
}

internal object MemorySegmentAccessProcessProbe {
    @JvmStatic fun main(args: Array<String>) {
        val access = MemorySegmentAccess(File(args[0]))
        val hold = { File(args[1]).writeText("locked"); while (true) Thread.sleep(100) }
        if (args[2].toBoolean()) access.maintenance(hold) else access.readWrite(hold)
    }
}
