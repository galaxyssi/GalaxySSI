package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.Executors

class MemorySegmentAccessTest {
    @get:Rule val temporary = TemporaryFolder()

    @Test fun nestedWrappersReuseTheSameProcessLock() {
        val path = File(temporary.root, "access.lock")
        val one = MemorySegmentAccess(path)
        val two = MemorySegmentAccess(path)
        assertEquals(7, one.readWrite { two.readWrite { 7 } })
        assertEquals(9, one.maintenance { two.readWrite { two.maintenance { 9 } } })
    }

    @Test fun upgradesFailAndExceptionsReleaseAllLocks() {
        val access = MemorySegmentAccess(File(temporary.root, "access.lock"))
        assertTrue(runCatching { access.readWrite { access.maintenance {} } }.isFailure)
        assertTrue(runCatching { access.maintenance { error("injected") } }.isFailure)
        assertEquals(3, access.maintenance { 3 })
    }

    @Test fun maintenanceWaitsUntilTheEntirePublicationOrReadFinishes() {
        val path = File(temporary.root, "access.lock")
        val started = CountDownLatch(1)
        val entered = CountDownLatch(1)
        val pool = Executors.newSingleThreadExecutor()
        try {
            MemorySegmentAccess(path).readWrite {
                pool.submit {
                    started.countDown()
                    MemorySegmentAccess(path).maintenance { entered.countDown() }
                }
                assertTrue(started.await(5, TimeUnit.SECONDS))
                assertFalse(entered.await(100, TimeUnit.MILLISECONDS))
            }
            assertTrue(entered.await(5, TimeUnit.SECONDS))
        } finally { pool.shutdownNow(); assertTrue(pool.awaitTermination(5, TimeUnit.SECONDS)) }
    }

    @Test fun backgroundMaintenanceDoesNotWaitForAnotherThread() {
        val path = File(temporary.root, "access.lock")
        val pool = Executors.newSingleThreadExecutor()
        try {
            MemorySegmentAccess(path).readWrite {
                val pending = pool.submit<Int?> { MemorySegmentAccess(path).tryMaintenance { fail("must not enter"); 1 } }
                assertNull(pending.get(1, TimeUnit.SECONDS))
            }
            assertEquals(7, MemorySegmentAccess(path).tryMaintenance { 7 })
        } finally { pool.shutdownNow(); assertTrue(pool.awaitTermination(5, TimeUnit.SECONDS)) }
    }

    @Test fun nonBlockingMaintenanceRejectsNestingAndReleasesOnFailure() {
        val access = MemorySegmentAccess(File(temporary.root, "access.lock"))
        assertTrue(runCatching { access.readWrite { access.tryMaintenance { 1 } } }.isFailure)
        assertTrue(runCatching { access.tryMaintenance { error("copy failed") } }.isFailure)
        assertEquals(7, access.readWrite { 7 })
        assertEquals(9, access.tryMaintenance { 9 })
    }
}
