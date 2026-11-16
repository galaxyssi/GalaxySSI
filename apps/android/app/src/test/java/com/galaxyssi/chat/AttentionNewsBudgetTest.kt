package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AttentionNewsBudgetTest {
    private val hour = 60 * ATTENTION_MINUTE
    private val now = 100 * hour

    @Test
    fun unreadTopicsUseTwelveHourSweepsEvenWhenCharging() {
        for (lastRead in listOf(0L, now - 24 * hour, now + hour)) {
            for (charging in listOf(false, true)) {
                val profile = AttentionNewsProfile.of(now, lastRead, charging)
                assertFalse(profile.recentlyRead)
                assertEquals(12 * hour, profile.feedInterval)
                assertFalse(profile.allowPush)
            }
        }
    }

    @Test
    fun onlyCompletedSweepsAreRescheduledOnPowerOrReadingChanges() {
        val oldInterval = 30 * ATTENTION_MINUTE
        val widerInterval = 12 * hour
        val planned = now + oldInterval
        assertEquals(now + widerInterval, AttentionNewsProfile.topicDueAt(now, planned, oldInterval, 0, widerInterval))
        assertEquals(planned, AttentionNewsProfile.topicDueAt(now, planned, oldInterval, 3, widerInterval))
        assertEquals(now, AttentionNewsProfile.topicDueAt(now, now, oldInterval, 0, widerInterval))
    }

    @Test
    fun readingChangesCadenceWithoutDroppingBatteryProtection() {
        val battery = AttentionNewsProfile.of(now, now - hour, false)
        val plugged = AttentionNewsProfile.of(now, now - hour, true)
        assertEquals(hour, battery.feedInterval)
        assertEquals(30 * ATTENTION_MINUTE, plugged.feedInterval)
        assertTrue(battery.articleLimit < plugged.articleLimit)
        assertFalse(battery.allowPush)
        assertTrue(plugged.allowPush)
    }

    @Test
    fun zeroOutputBackoffAndPowerChangeUsePersistedBatchTimestamp() {
        val active = AttentionNewsProfile(true, false)
        val idle = AttentionNewsProfile(false, false)
        val charging = AttentionNewsProfile(false, true)
        val lastBatch = now - 11 * ATTENTION_MINUTE
        assertEquals(34 * ATTENTION_MINUTE,
            AttentionNewsProfile.remaining(now, lastBatch, active.articleSpacing(false)))
        assertEquals(4 * ATTENTION_MINUTE,
            AttentionNewsProfile.remaining(now, lastBatch, active.articleSpacing(true)))
        assertEquals(12 * hour - 11 * ATTENTION_MINUTE,
            AttentionNewsProfile.remaining(now, lastBatch, idle.articleSpacing(false)))
        assertEquals(0L, AttentionNewsProfile.remaining(now, lastBatch, charging.articleSpacing(false)))
    }

    @Test
    fun tenPercentOfOneCoreSuspendsNewsForFiveMinutes() {
        val cpu = AttentionNewsCpuWindow()
        assertEquals(0L, cpu.delay(1_000L, 500L))
        assertEquals(0L, cpu.delay(6_000L, 1_000L))
        assertEquals(5 * ATTENTION_MINUTE, cpu.delay(11_000L, 1_500L))
        assertEquals(4 * ATTENTION_MINUTE, cpu.delay(71_000L, 1_600L))
        assertEquals(0L, cpu.delay(311_000L, 1_600L))
        assertEquals(0L, cpu.delay(321_000L, 2_599L))
    }

    @Test
    fun idleGapsDoNotChargeAnOldCpuSampleToTheNextBatch() {
        val cpu = AttentionNewsCpuWindow()
        assertEquals(0L, cpu.delay(1_000L, 1_000L))
        assertEquals(0L, cpu.delay(121_000L, 100_000L))
        assertEquals(5 * ATTENTION_MINUTE, cpu.delay(131_000L, 101_500L))
    }
}
