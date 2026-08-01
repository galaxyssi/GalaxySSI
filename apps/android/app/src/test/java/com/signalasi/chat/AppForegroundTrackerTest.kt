package com.signalasi.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AppForegroundTrackerTest {
    @Test
    fun duplicateForegroundRegistrationIsIdempotent() {
        val activity = Any()

        AppForegroundTracker.onActivityForeground(activity)
        AppForegroundTracker.onActivityForeground(activity)
        assertTrue(AppForegroundTracker.isForeground())

        AppForegroundTracker.onActivityBackground(activity)
        assertFalse(AppForegroundTracker.isForeground())
    }

    @Test
    fun anotherForegroundActivityKeepsTheAppForeground() {
        val firstActivity = Any()
        val secondActivity = Any()

        AppForegroundTracker.onActivityForeground(firstActivity)
        AppForegroundTracker.onActivityForeground(secondActivity)
        AppForegroundTracker.onActivityBackground(firstActivity)
        assertTrue(AppForegroundTracker.isForeground())

        AppForegroundTracker.onActivityBackground(secondActivity)
        assertFalse(AppForegroundTracker.isForeground())
    }
}
