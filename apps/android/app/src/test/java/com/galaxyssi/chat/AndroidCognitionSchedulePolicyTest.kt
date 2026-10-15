package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class AndroidCognitionSchedulePolicyTest {
    @Test fun `paused learning rejects event research explicit and retry wakeups`() {
        AndroidCognitionWorkMode.entries.forEach { mode ->
            assertEquals(mode == AndroidCognitionWorkMode.PROJECTION,
                AndroidCognitionScheduler.allowsWork(mode, false))
            assertEquals(true, AndroidCognitionScheduler.allowsWork(mode, true))
        }
    }

    @Test fun `attention continuation does not run unrelated cognition or knowledge projection`() {
        val plan = AndroidCognitionSchedulePolicy.workPlan(AndroidCognitionWorkMode.ATTENTION)
        assertEquals(false, plan.runBatchCognition)
        assertEquals(0, plan.cycleCount)
        assertEquals(false, plan.projectKnowledge)
    }

    @Test
    fun `message events use only the lightweight processing path`() {
        val plan = AndroidCognitionSchedulePolicy.workPlan(AndroidCognitionWorkMode.EVENT)

        assertEquals(12, plan.eventLimit)
        assertEquals(false, plan.runBatchCognition)
        assertEquals(0, plan.cycleCount)
        assertEquals(false, plan.projectKnowledge)
    }

    @Test
    fun `scheduled and explicit work enable bounded batch cognition`() {
        assertEquals(1, AndroidCognitionSchedulePolicy.workPlan(AndroidCognitionWorkMode.SCHEDULED).cycleCount)
        assertEquals(2, AndroidCognitionSchedulePolicy.workPlan(AndroidCognitionWorkMode.EXPLICIT).cycleCount)
        assertEquals(true, AndroidCognitionSchedulePolicy.workPlan(AndroidCognitionWorkMode.PROJECTION).projectKnowledge)
    }

    @Test
    fun `active work schedules the ten minute cadence`() {
        assertEquals(
            AndroidCognitionSchedulePolicy.MIN_DELAY_MILLIS,
            AndroidCognitionSchedulePolicy.nextExplorationDelayMillis(
                pendingEvents = 1,
                activeCognition = 0,
                activeResearch = 0,
                pendingInsights = 0
            )
        )
    }

    @Test
    fun `pending insights schedule a thirty minute cadence`() {
        assertEquals(
            30L * 60L * 1_000L,
            AndroidCognitionSchedulePolicy.nextExplorationDelayMillis(0, 0, 0, 1)
        )
    }

    @Test
    fun `idle cognition never waits longer than four hours`() {
        assertEquals(
            AndroidCognitionSchedulePolicy.MAX_DELAY_MILLIS,
            AndroidCognitionSchedulePolicy.nextExplorationDelayMillis(0, 0, 0, 0)
        )
    }
}
