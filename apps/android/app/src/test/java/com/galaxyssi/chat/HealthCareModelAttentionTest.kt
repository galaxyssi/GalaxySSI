package com.galaxyssi.chat

import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthCareModelAttentionTest {
    private fun id() = UUID.randomUUID().toString()
    @Test fun noticePayloadHasExactScopeAndState() {
        val value = HealthCareModelAttention(id(), id(), id(), 1000)
        assertEquals(value, HealthCareModelAttention.from(value.json()))
        HealthCareAttentionState.entries.forEach { state ->
            assertEquals(value.copy(state = state), HealthCareModelAttention.from(value.copy(state = state).json()))
        }
        assertThrows(IllegalArgumentException::class.java) { value.copy(concernId = "wrong") }
        assertThrows(IllegalArgumentException::class.java) { value.copy(createdAt = 0) }
    }
    @Test fun visibilityBelongsToTheExactHealthConversationAndDatabase() {
        val owner = Any(); val another = Any()
        try {
            assertTrue(HealthCareModelReviewVisibility.show(owner, "fixture", "health-thread"))
            assertFalse(HealthCareModelReviewVisibility.show(owner, "fixture", "health-thread"))
            assertTrue(HealthCareModelReviewVisibility.contains("fixture", "health-thread"))
            assertFalse(HealthCareModelReviewVisibility.contains("fixture", "ordinary-thread"))
            assertFalse(HealthCareModelReviewVisibility.contains("another", "health-thread"))
            HealthCareModelReviewVisibility.show(another, "fixture", "health-thread")
            assertTrue(HealthCareModelReviewVisibility.hide(owner))
            assertTrue(HealthCareModelReviewVisibility.contains("fixture", "health-thread"))
            HealthCareModelReviewVisibility.hide(another)
            assertFalse(HealthCareModelReviewVisibility.contains("fixture", "health-thread"))
        } finally { HealthCareModelReviewVisibility.hide(owner); HealthCareModelReviewVisibility.hide(another) }
    }
    @Test fun modelNotificationsKeepTheExistingGlobalOptInAndSaveTheirOwnToggle() {
        val initial = HealthReminderSettings()
        assertFalse(initial.notifications); assertTrue(initial.modelReviews)
        assertEquals(initial, HealthReminderSettings.from(initial.json()))
        val disabled = initial.copy(modelReviews = false, notifications = true)
        assertEquals(disabled, HealthReminderSettings.from(disabled.json()))
        assertTrue(HealthReminderSettings.from(initial.json().apply { remove("modelReviews") }).modelReviews)
        assertFalse(HealthReminderSettings.from(initial.json().apply { remove("modelReviews") }).notifications)
    }
}
