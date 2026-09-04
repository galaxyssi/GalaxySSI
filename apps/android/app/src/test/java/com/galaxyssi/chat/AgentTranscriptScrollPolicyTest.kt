package com.galaxyssi.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentTranscriptScrollPolicyTest {
    @Test
    fun layoutChangesDoNotDisableAutoFollow() {
        assertTrue(
            AgentTranscriptScrollPolicy.nextAutoFollow(
                current = true,
                userScrollActive = false,
                itemCount = 3,
                lastVisiblePosition = 2,
                remainingPx = 600,
                thresholdPx = 56
            )
        )
    }

    @Test
    fun userScrollControlsAutoFollow() {
        assertFalse(
            AgentTranscriptScrollPolicy.nextAutoFollow(
                current = true,
                userScrollActive = true,
                itemCount = 3,
                lastVisiblePosition = 1,
                remainingPx = Int.MAX_VALUE,
                thresholdPx = 56
            )
        )
        assertTrue(
            AgentTranscriptScrollPolicy.nextAutoFollow(
                current = false,
                userScrollActive = true,
                itemCount = 3,
                lastVisiblePosition = 2,
                remainingPx = 20,
                thresholdPx = 56
            )
        )
    }

    @Test
    fun upwardScrollNearStartLoadsOlderHistory() {
        assertTrue(
            AgentTranscriptScrollPolicy.shouldLoadOlderFromScroll(
                dy = -8,
                firstVisiblePosition = 1,
                hydrationPending = false
            )
        )
    }

    @Test
    fun downwardPullAtAbsoluteTopLoadsOlderHistory() {
        assertTrue(
            AgentTranscriptScrollPolicy.shouldLoadOlderFromPull(
                downY = 200f,
                currentY = 240f,
                canScrollUp = false,
                hydrationPending = false,
                thresholdPx = 24
            )
        )
    }

    @Test
    fun ordinaryScrollingDoesNotTriggerTopPagination() {
        assertFalse(
            AgentTranscriptScrollPolicy.shouldLoadOlderFromScroll(
                dy = 12,
                firstVisiblePosition = 0,
                hydrationPending = false
            )
        )
        assertFalse(
            AgentTranscriptScrollPolicy.shouldLoadOlderFromPull(
                downY = 200f,
                currentY = 240f,
                canScrollUp = true,
                hydrationPending = false,
                thresholdPx = 24
            )
        )
    }

    @Test
    fun hydrationBlocksPagination() {
        assertFalse(
            AgentTranscriptScrollPolicy.shouldLoadOlderFromScroll(
                dy = -8,
                firstVisiblePosition = 0,
                hydrationPending = true
            )
        )
        assertFalse(
            AgentTranscriptScrollPolicy.shouldLoadOlderFromPull(
                downY = 200f,
                currentY = 240f,
                canScrollUp = false,
                hydrationPending = true,
                thresholdPx = 24
            )
        )
    }
}
