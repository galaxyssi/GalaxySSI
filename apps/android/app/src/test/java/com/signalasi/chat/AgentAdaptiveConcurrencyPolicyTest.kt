package com.signalasi.chat

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentAdaptiveConcurrencyPolicyTest {
    @Test
    fun policySupportsOneToSixtyFourAndKeepsReasoningCpuBound() {
        val workstation = signals(processors = 32, availableGib = 20)
        val phone = signals(processors = 8, availableGib = 8)

        assertEquals(
            64,
            AgentAdaptiveConcurrencyPolicy.limit(
                workstation,
                AgentConcurrencyWorkload.NATIVE_READ_IO
            )
        )
        assertEquals(
            64,
            AgentAdaptiveConcurrencyPolicy.limit(phone, AgentConcurrencyWorkload.NATIVE_READ_IO)
        )
        assertEquals(
            16,
            AgentAdaptiveConcurrencyPolicy.limit(phone, AgentConcurrencyWorkload.READ_REASONING)
        )
        assertEquals(
            32,
            AgentAdaptiveConcurrencyPolicy.limit(phone, AgentConcurrencyWorkload.NATIVE_MUTATION)
        )
    }

    @Test
    fun memoryCpuAndThermalPressureReduceNewAdmissions() {
        val healthy = signals(processors = 8, availableGib = 8)

        assertEquals(
            2,
            AgentAdaptiveConcurrencyPolicy.limit(
                healthy.copy(availableMemoryBytes = 128L * MIB),
                AgentConcurrencyWorkload.NATIVE_READ_IO
            )
        )
        assertEquals(
            32,
            AgentAdaptiveConcurrencyPolicy.limit(
                healthy.copy(thermalStatus = 2),
                AgentConcurrencyWorkload.NATIVE_READ_IO
            )
        )
        assertEquals(
            16,
            AgentAdaptiveConcurrencyPolicy.limit(
                healthy.copy(cpuLoadPercent = 94),
                AgentConcurrencyWorkload.NATIVE_READ_IO
            )
        )
        assertEquals(
            1,
            AgentAdaptiveConcurrencyPolicy.limit(
                healthy.copy(lowMemory = true),
                AgentConcurrencyWorkload.NATIVE_READ_IO
            )
        )
    }

    @Test
    fun blockingGateUsesCurrentLimitAndAdmitsBeyondLegacyFour() {
        val configuredLimit = AtomicInteger(6)
        val gate = AgentAdaptiveBlockingPermitGate(configuredLimit::get)
        val entered = CountDownLatch(6)
        val release = CountDownLatch(1)
        val seventhEntered = CountDownLatch(1)
        val pool = Executors.newFixedThreadPool(7)
        try {
            repeat(6) {
                pool.submit {
                    gate.acquire {}
                    try {
                        entered.countDown()
                        release.await()
                    } finally {
                        gate.release()
                    }
                }
            }
            assertTrue(entered.await(2, TimeUnit.SECONDS))
            pool.submit {
                gate.acquire {}
                try {
                    seventhEntered.countDown()
                } finally {
                    gate.release()
                }
            }
            assertFalse(seventhEntered.await(150, TimeUnit.MILLISECONDS))
            release.countDown()
            assertTrue(seventhEntered.await(2, TimeUnit.SECONDS))
        } finally {
            release.countDown()
            pool.shutdownNow()
        }
    }

    @Test
    fun blockingGateStopsNewAdmissionsWhenCapacityShrinks() {
        val configuredLimit = AtomicInteger(2)
        val gate = AgentAdaptiveBlockingPermitGate(configuredLimit::get)
        val firstEntered = CountDownLatch(1)
        val secondEntered = CountDownLatch(1)
        val releaseFirst = CountDownLatch(1)
        val releaseSecond = CountDownLatch(1)
        val thirdEntered = CountDownLatch(1)
        val pool = Executors.newFixedThreadPool(3)
        try {
            pool.submit {
                gate.acquire {}
                try {
                    firstEntered.countDown()
                    releaseFirst.await()
                } finally {
                    gate.release()
                }
            }
            assertTrue(firstEntered.await(2, TimeUnit.SECONDS))
            pool.submit {
                gate.acquire {}
                try {
                    secondEntered.countDown()
                    releaseSecond.await()
                } finally {
                    gate.release()
                }
            }
            assertTrue(secondEntered.await(2, TimeUnit.SECONDS))

            configuredLimit.set(1)
            pool.submit {
                gate.acquire {}
                try {
                    thirdEntered.countDown()
                } finally {
                    gate.release()
                }
            }
            releaseFirst.countDown()
            assertFalse(thirdEntered.await(200, TimeUnit.MILLISECONDS))
            releaseSecond.countDown()
            assertTrue(thirdEntered.await(2, TimeUnit.SECONDS))
        } finally {
            releaseFirst.countDown()
            releaseSecond.countDown()
            pool.shutdownNow()
        }
    }

    private fun signals(
        processors: Int,
        availableGib: Long
    ) = AgentAdaptiveConcurrencySignals(
        logicalProcessorCount = processors,
        totalMemoryBytes = 24L * GIB,
        availableMemoryBytes = availableGib * GIB,
        lowMemory = false,
        thermalStatus = 0,
        cpuLoadPercent = 10
    )

    private companion object {
        const val MIB = 1024L * 1024L
        const val GIB = 1024L * MIB
    }
}
