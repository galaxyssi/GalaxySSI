package com.galaxyssi.chat

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

    @Test
    fun visibleConversationIsRestoredWhenActivityReturnsToForeground() {
        val activity = Any()
        val contactId = "galaxyssi:0123456789abcdef"

        AppForegroundTracker.onActivityForeground(activity)
        AppForegroundTracker.onConversationVisible(activity, contactId)
        AppForegroundTracker.onActivityBackground(activity)
        assertFalse(AppForegroundTracker.isConversationVisible(contactId))

        AppForegroundTracker.onActivityForeground(activity, contactId)
        assertTrue(AppForegroundTracker.isConversationVisible(contactId))

        AppForegroundTracker.onActivityBackground(activity)
    }
}
