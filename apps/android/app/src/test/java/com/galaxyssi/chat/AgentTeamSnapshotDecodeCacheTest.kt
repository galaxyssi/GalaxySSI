package com.galaxyssi.chat

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test

class AgentTeamSnapshotDecodeCacheTest {
    private val snapshot = AgentTeamExecutionSnapshot("run", "team", "conversation", "turn", "agent", "Goal",
        AgentTeamVisibilityMode.VISIBLE, AgentTeamExecutionState.RUNNING, emptyList(), updatedAtMillis = 10)

    @Test fun unchangedRowsDecodeOnceButChangedCiphertextAndDatabaseNeverReuseOldState() {
        val cache = AgentTeamSnapshotDecodeCache()
        var decodes = 0
        repeat(1000) {
            assertEquals(snapshot, cache.getOrDecode("database-a\u0000run", "cipher-a") { decodes++; snapshot })
        }
        assertEquals(1, decodes)
        val correction = snapshot.copy(finalOutput = "Correction", state = AgentTeamExecutionState.SUCCEEDED)
        assertEquals(correction, cache.getOrDecode("database-a\u0000run", "cipher-b") { decodes++; correction })
        assertEquals(snapshot, cache.getOrDecode("database-b\u0000run", "cipher-a") { decodes++; snapshot })
        assertEquals(3, decodes)
    }

    @Test fun expiryIsFixedAndBackgroundClearForcesFreshDecode() {
        var now = 0L
        var decodes = 0
        val cache = AgentTeamSnapshotDecodeCache(clock = { now })
        fun read() = cache.getOrDecode("key", "cipher") { decodes++; snapshot }
        read()
        now = RuntimeCachePolicy.SENSITIVE_TTL_NANOS - 1
        read()
        assertEquals(1, decodes)
        now++
        read()
        assertEquals(2, decodes)
        RuntimeSensitiveCaches.clearAll()
        read()
        assertEquals(3, decodes)
    }

    @Test fun countByteBudgetAndFailedDecodeRemainBoundedAndRecoverable() {
        val cache = AgentTeamSnapshotDecodeCache(capacity = 1, maxCharacters = 100)
        var decodes = 0
        fun read(key: String, ciphertext: String = "cipher") = cache.getOrDecode(key, ciphertext) { decodes++; snapshot }
        read("first"); read("second"); read("first")
        assertEquals(3, decodes)
        repeat(2) { cache.getOrDecode("large", "large-cipher") { decodes++; snapshot.copy(goal = "x".repeat(101)) } }
        assertEquals(5, decodes)
        assertNull(cache.getOrDecode("first", "changed") { null })
        read("first", "changed")
        assertEquals(6, decodes)
    }

    @Test fun cachedMembersCannotBeMutatedThroughSharedLists() {
        val names = mutableListOf("dependency")
        val members = mutableListOf(AgentTeamMemberSnapshot("agent", "role", AgentDeliveryMode.RESPOND,
            AgentSubagentStatus.QUEUED, pendingDependencyNames = names))
        val cache = AgentTeamSnapshotDecodeCache()
        val cached = requireNotNull(cache.getOrDecode("key", "cipher") { snapshot.copy(members = members) })
        names.clear(); members.clear()
        assertEquals(listOf("dependency"), cached.members.single().pendingDependencyNames)
        assertThrows(UnsupportedOperationException::class.java) { (cached.members as MutableList<AgentTeamMemberSnapshot>).clear() }
        assertThrows(UnsupportedOperationException::class.java) {
            (cached.members.single().pendingDependencyNames as MutableList<String>).clear()
        }
    }

    @Test fun backgroundClearDoesNotWaitForDecodeOrAllowItsResultToRepopulateTheCache() {
        val cache = AgentTeamSnapshotDecodeCache()
        val started = CountDownLatch(1)
        val release = CountDownLatch(1)
        val executor = Executors.newFixedThreadPool(2)
        try {
            val decoding = executor.submit<AgentTeamExecutionSnapshot?> {
                cache.getOrDecode("key", "cipher") {
                    started.countDown()
                    check(release.await(5, TimeUnit.SECONDS))
                    snapshot
                }
            }
            assertTrue(started.await(5, TimeUnit.SECONDS))
            executor.submit { cache.clearSensitive() }.get(1, TimeUnit.SECONDS)
            release.countDown()
            assertEquals(snapshot, decoding.get(5, TimeUnit.SECONDS))
            var decodedAgain = false
            cache.getOrDecode("key", "cipher") { decodedAgain = true; snapshot }
            assertTrue(decodedAgain)
        } finally { release.countDown(); executor.shutdownNow() }
    }
}
