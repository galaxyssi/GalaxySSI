package com.galaxyssi.chat

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class AgentRecoveryTransferRegistryTest {
    private val identity = listOf("desktop", "route", "conversation", "task", "turn", "contact", "123", "agent")

    @Test fun noTransferNeverSuppressesDiscovery() {
        val registry = AgentRecoveryTransferRegistry()
        assertFalse(registry.deferDiscovery(identity) { error("No fence lookup needed") })
    }

    @Test fun repeatedWakesCoalesceAndReleaseExactlyOnce() {
        val registry = AgentRecoveryTransferRegistry()
        val lease = requireNotNull(registry.begin(identity, 2))
        repeat(1000) { assertTrue(registry.deferDiscovery(identity) { it == 2L }) }
        assertTrue(registry.finish(lease))
        assertFalse(registry.finish(lease))
        assertEquals(0, registry.activeCount)
        assertFalse(registry.deferDiscovery(identity) { true })
        assertNotNull(registry.begin(identity, 2))
    }

    @Test fun finishingWithoutDeferredWakeDoesNotCreateRetryLoop() {
        val registry = AgentRecoveryTransferRegistry()
        repeat(10) { assertFalse(registry.finish(requireNotNull(registry.begin(identity, 1)))) }
    }

    @Test fun everyIdentityDimensionIsIsolated() {
        val registry = AgentRecoveryTransferRegistry()
        val original = requireNotNull(registry.begin(identity, 1))
        identity.indices.forEach { index ->
            val other = identity.toMutableList().also { it[index] += "-other" }
            assertFalse(registry.deferDiscovery(other) { true })
            val independent = requireNotNull(registry.begin(other, 1))
            assertTrue(registry.deferDiscovery(other) { true })
            assertTrue(registry.finish(independent))
        }
        assertFalse(registry.finish(original))
    }

    @Test fun cancelledOrSupersededTaskDoesNotSuppressNewObservation() {
        val registry = AgentRecoveryTransferRegistry()
        val lease = requireNotNull(registry.begin(identity, 1))
        assertFalse(registry.deferDiscovery(identity) { false })
        assertFalse(registry.finish(lease))
    }

    @Test fun newerGenerationCannotBeRemovedByOldCompletion() {
        val registry = AgentRecoveryTransferRegistry()
        val old = requireNotNull(registry.begin(identity, 1))
        assertTrue(registry.deferDiscovery(identity) { true })
        val current = requireNotNull(registry.begin(identity, 2))
        assertNull(registry.begin(identity, 1))
        assertNull(registry.begin(identity, 2))
        assertTrue(registry.finish(old))
        assertEquals(1, registry.activeCount)
        assertTrue(registry.deferDiscovery(identity) { it == 2L })
        assertTrue(registry.finish(current))
        assertEquals(0, registry.activeCount)
    }

    @Test fun completedTransferDuringFenceCheckIsNotSuppressed() {
        val registry = AgentRecoveryTransferRegistry()
        val lease = requireNotNull(registry.begin(identity, 1))
        assertFalse(registry.deferDiscovery(identity) {
            assertFalse(registry.finish(lease)); true
        })
    }

    @Test fun newTransferDuringFenceCheckIsNotSuppressedUsingStaleVerdict() {
        val registry = AgentRecoveryTransferRegistry()
        registry.begin(identity, 1)
        assertFalse(registry.deferDiscovery(identity) {
            assertNotNull(registry.begin(identity, 2)); true
        })
    }

    @Test fun fenceExceptionDoesNotLeaveDeferredWork() {
        val registry = AgentRecoveryTransferRegistry()
        val lease = requireNotNull(registry.begin(identity, 1))
        assertTrue(runCatching { registry.deferDiscovery(identity) { error("database unavailable") } }.isFailure)
        assertFalse(registry.finish(lease))
    }

    @Test fun identityIsSnapshotNotMutableCallerList() {
        val registry = AgentRecoveryTransferRegistry()
        val mutable = identity.toMutableList()
        val lease = requireNotNull(registry.begin(mutable, 1))
        mutable[0] = "changed"
        assertTrue(registry.deferDiscovery(identity) { true })
        assertTrue(registry.finish(lease))
        assertEquals(0, registry.activeCount)
    }

    @Test fun concurrentRequestsHaveOneOwner() {
        val registry = AgentRecoveryTransferRegistry()
        val executor = Executors.newFixedThreadPool(8)
        try {
            val owners = (1..64).map { executor.submit<AgentRecoveryTransferRegistry.Lease?> {
                registry.begin(identity, 1)
            } }.mapNotNull { it.get(5, TimeUnit.SECONDS) }
            assertEquals(1, owners.size)
            assertFalse(registry.finish(owners.single()))
        } finally { executor.shutdownNow() }
    }

    @Test fun databaseFenceDoesNotBlockUnrelatedTransfer() {
        val registry = AgentRecoveryTransferRegistry()
        registry.begin(identity, 1)
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val executor = Executors.newFixedThreadPool(2)
        try {
            val check = executor.submit<Boolean> { registry.deferDiscovery(identity) {
                entered.countDown(); check(release.await(5, TimeUnit.SECONDS)); true
            } }
            assertTrue(entered.await(5, TimeUnit.SECONDS))
            val unrelated = executor.submit<AgentRecoveryTransferRegistry.Lease?> {
                registry.begin(identity + "unrelated", 1)
            }.get(2, TimeUnit.SECONDS)
            assertNotNull(unrelated)
            release.countDown()
            assertTrue(check.get(5, TimeUnit.SECONDS))
        } finally { release.countDown(); executor.shutdownNow() }
    }

    @Test fun racingCompletionNeverLosesAnAcknowledgedDeferredWake() {
        val executor = Executors.newFixedThreadPool(2)
        try {
            repeat(200) {
                val registry = AgentRecoveryTransferRegistry()
                val lease = requireNotNull(registry.begin(identity, 1))
                val start = CountDownLatch(1)
                val deferred = executor.submit<Boolean> {
                    check(start.await(5, TimeUnit.SECONDS))
                    registry.deferDiscovery(identity) { true }
                }
                val completed = executor.submit<Boolean> {
                    check(start.await(5, TimeUnit.SECONDS))
                    registry.finish(lease)
                }
                start.countDown()
                assertEquals(deferred.get(5, TimeUnit.SECONDS), completed.get(5, TimeUnit.SECONDS))
                assertEquals(0, registry.activeCount)
            }
        } finally { executor.shutdownNow() }
    }

    @Test fun cancellationBeforeCoroutineBodyStillReleasesDeferredWake(): Unit = runBlocking {
        val registry = AgentRecoveryTransferRegistry()
        val lease = requireNotNull(registry.begin(identity, 1))
        assertTrue(registry.deferDiscovery(identity) { true })
        val releases = AtomicInteger()
        val job = launch(start = CoroutineStart.LAZY) { error("Must not run") }
        job.invokeOnCompletion { if (registry.finish(lease)) releases.incrementAndGet() }
        job.cancel(); job.join()
        assertEquals(1, releases.get())
        assertEquals(0, registry.activeCount)
    }

    @Test fun failedBodyReplaysOneWakeAfterReconnectWithoutBlockingOtherTasks() {
        val registry = AgentRecoveryTransferRegistry()
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        try {
            val lease = requireNotNull(registry.begin(identity, 1))
            var connected = true
            var queryCount = 0
            var unrelatedQueries = 0
            val wake = AgentRecoveryWakeCoordinator(scope, recover = {
                if (!registry.deferDiscovery(identity) { true }) queryCount++
                unrelatedQueries++
            })
            wake.connectionChanged(true)
            assertEquals(0, queryCount)
            assertEquals(1, unrelatedQueries)
            connected = false
            wake.connectionChanged(false)
            if (registry.finish(lease)) wake.request(isConnected = connected)
            assertEquals(0, queryCount)
            wake.connectionChanged(true)
            assertEquals(1, queryCount)
            assertEquals(2, unrelatedQueries)
            assertFalse(wake.hasPendingWake)
        } finally { scope.cancel() }
    }

    @Test fun successfulBodyRechecksDurableEligibilityInsteadOfRediscovering() {
        val registry = AgentRecoveryTransferRegistry()
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        try {
            var pending = true
            var queries = 0
            val wake = AgentRecoveryWakeCoordinator(scope, recover = {
                if (pending && !registry.deferDiscovery(identity) { true }) queries++
            })
            val lease = requireNotNull(registry.begin(identity, 1))
            wake.connectionChanged(true)
            pending = false
            if (registry.finish(lease)) wake.request(isConnected = true)
            assertEquals(0, queries)
            assertEquals(0, registry.activeCount)
        } finally { scope.cancel() }
    }
}
