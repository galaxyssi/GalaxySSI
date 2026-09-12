package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class KnowledgeSegmentLeasesTest {
    @get:Rule val temporary = TemporaryFolder()
    @Test fun snapshotAllowsAnotherThreadToWriteButNotReclaim() {
        val path = File(temporary.root, "knowledge.lock")
        val one = KnowledgeSegmentLeases(path)
        val two = KnowledgeSegmentLeases(path)
        val snapshot = one.acquire()
        val executor = Executors.newSingleThreadExecutor()
        try {
            assertEquals(7, executor.submit<Int> { two.access { 7 } }.get(1, TimeUnit.SECONDS))
            assertNull(executor.submit<Int?> { two.tryReclaim { 9 } }.get(1, TimeUnit.SECONDS))
            executor.submit { snapshot.close() }.get(1, TimeUnit.SECONDS)
            snapshot.close()
            assertEquals(9, two.tryReclaim { 9 })
        } finally { snapshot.close(); executor.shutdownNow(); assertTrue(executor.awaitTermination(5, TimeUnit.SECONDS)) }
    }
    @Test fun lastLeaseControlsReclamationAndExceptionsReleaseAccess() {
        val leases = KnowledgeSegmentLeases(File(temporary.root, "knowledge.lock"))
        val first = leases.acquire(); val second = leases.acquire()
        first.close(); assertNull(leases.tryReclaim { 1 })
        second.close()
        assertThrows(IllegalStateException::class.java) { leases.access { error("fixture") } }
        assertThrows(IllegalStateException::class.java) { leases.tryReclaim { error("fixture") } }
        assertEquals(2, leases.tryReclaim { 2 })
        assertThrows(IllegalStateException::class.java) { leases.tryReclaim { leases.acquire() } }
        assertEquals(3, leases.access { 3 })
    }
}
