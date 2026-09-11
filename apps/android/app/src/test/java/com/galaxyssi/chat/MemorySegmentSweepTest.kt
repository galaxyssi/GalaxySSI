package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CancellationException

class MemorySegmentSweepTest {
    @Test fun finishesWhenTheDurableCycleIsComplete() {
        var calls = 0
        val sweep = MemorySegmentSweep({ false }, { ++calls == 3 }, { 0 })
        assertEquals(MemorySegmentSweep.Outcome.COMPLETE, sweep.run())
        assertEquals(3, calls)
    }

    @Test fun foregroundOrStopBeforeStartDoesNoStorageWork() {
        val sweep = MemorySegmentSweep({ true }, { error("must not touch storage") })
        assertEquals(MemorySegmentSweep.Outcome.DEFERRED, sweep.run())
    }

    @Test fun busyStoreYieldsWithoutPollingOrConsumingTheNextPage() {
        var calls = 0
        val sweep = MemorySegmentSweep({ false }, { calls++; null })
        assertEquals(MemorySegmentSweep.Outcome.DEFERRED, sweep.run())
        assertEquals(1, calls)
    }

    @Test fun foregroundChangeCanInterruptAnInFlightCopy() {
        var foreground = false
        var published = false
        val sweep = MemorySegmentSweep({ foreground }, { check ->
            foreground = true
            check()
            published = true
            true
        })
        assertEquals(MemorySegmentSweep.Outcome.DEFERRED, sweep.run())
        assertFalse(published)
    }

    @Test fun quantumExpiryStopsBeforeStartingAnotherStorageTransaction() {
        var nanos = 0L
        var calls = 0
        val sweep = MemorySegmentSweep({ false }, { calls++; nanos = 100; false }, { nanos }, 100)
        assertEquals(MemorySegmentSweep.Outcome.DEFERRED, sweep.run())
        assertEquals(1, calls)
    }

    @Test fun quantumExpiryIsCheckedInsideCopiesToo() {
        var nanos = 0L
        val sweep = MemorySegmentSweep({ false }, { check -> nanos = 100; check(); true }, { nanos }, 100)
        assertEquals(MemorySegmentSweep.Outcome.DEFERRED, sweep.run())
    }

    @Test fun storageFailureAndCancellationAreNotSuccessfulEmptyCycles() {
        for (error in listOf(IllegalStateException("corruption"), CancellationException("stopped"))) {
            val result = runCatching { MemorySegmentSweep({ false }, { throw error }).run() }
            assertSame(error, result.exceptionOrNull())
        }
    }

    @Test fun noHardActionOrSegmentCountStopsAHealthySweep() {
        var calls = 0
        assertEquals(MemorySegmentSweep.Outcome.COMPLETE,
            MemorySegmentSweep({ false }, { ++calls == 10_001 }, { 0 }).run())
        assertEquals(10_001, calls)
    }
}
