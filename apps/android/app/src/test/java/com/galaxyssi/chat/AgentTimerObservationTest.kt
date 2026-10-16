package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentTimerObservationTest {
    private fun node(id: String, text: String = "", description: String = "", clickable: Boolean = false) =
        PhoneUiNode(id, text, description, "${AgentTimerObservation.PACKAGE}:id/$id", "android.widget.View",
            "", clickable, false, false, false, true, null, false)

    @Test fun pausedClockFrameRequiresUniqueMatchingTimerAndEnabledControl() {
        val frame = PhoneUiSnapshot(1, AgentTimerObservation.PACKAGE, "fixture", listOf(
            node("timer_name_view", "GalaxySSI-fixture"), node("timer_time_view", description = "23 秒钟"),
            node("timer_resume_button", clickable = true), node("timer_cancel_button", clickable = true)), false, 1000)
        assertEquals(AgentTimerObservation.Sample("GalaxySSI-fixture", 23, true, 1000),
            AgentTimerObservation.read(frame, "GalaxySSI-fixture"))
        assertEquals("timer_resume_button", AgentTimerObservation.control(frame, "GalaxySSI-fixture", "resume")?.path)
        assertNull(AgentTimerObservation.read(frame, "another"))
        assertNull(AgentTimerObservation.read(frame.copy(truncated = true), "GalaxySSI-fixture"))
        assertNull(AgentTimerObservation.read(frame.copy(nodes = frame.nodes + node("timer_name_view", "other")), "GalaxySSI-fixture"))
        assertNull(AgentTimerObservation.control(frame.copy(nodes = frame.nodes.map { it.copy(clickable = false) }),
            "GalaxySSI-fixture", "resume"))
    }
    private fun sample(seconds: Int, time: Long = 1000, paused: Boolean = false, label: String = "fixture") =
        AgentTimerObservation.Sample(label, seconds, paused, time)
    @Test fun runningNeedsIdentityAndActualTimeDecrease() {
        assertTrue(AgentTimerObservation.provesRunning(sample(60), sample(58, 3000), 60))
        assertFalse(AgentTimerObservation.provesRunning(sample(60), sample(60, 3000), 60))
        assertFalse(AgentTimerObservation.provesRunning(sample(60), sample(58, 3000, label = "another"), 60))
        assertFalse(AgentTimerObservation.provesRunning(sample(120), sample(118, 3000), 60))
        assertFalse(AgentTimerObservation.provesRunning(sample(60), sample(10, 3000), 60))
        assertFalse(AgentTimerObservation.provesRunning(sample(10), sample(8, 3000), 60, minimumRemaining = 55))
    }
    @Test fun pausedNeedsStableTimeAndResumeState() {
        assertTrue(AgentTimerObservation.provesPaused(sample(40, paused = true), sample(40, 2500, true)))
        assertFalse(AgentTimerObservation.provesPaused(sample(40), sample(40, 2500)))
        assertFalse(AgentTimerObservation.provesPaused(sample(40, paused = true), sample(39, 2500, true)))
    }
    @Test fun absentObservationNeverProvesCompletion() {
        assertFalse(AgentTimerObservation.provesRunning(null, sample(59), 60))
        assertFalse(AgentTimerObservation.provesPaused(null, null))
        assertNull(AgentTimerObservation.read(null, "fixture"))
    }
    @Test fun removalNeedsACompleteRecognizableClockFrameWithoutTheTarget() {
        val empty = PhoneUiSnapshot(1, AgentTimerObservation.PACKAGE, "fixture",
            listOf(node("timer_start_button")), false, 1000)
        assertTrue(AgentTimerObservation.provesRemoved(empty, "GalaxySSI-fixture"))
        assertFalse(AgentTimerObservation.provesRemoved(null, "GalaxySSI-fixture"))
        assertFalse(AgentTimerObservation.provesRemoved(empty.copy(packageName = "other.app"), "GalaxySSI-fixture"))
        assertFalse(AgentTimerObservation.provesRemoved(empty.copy(truncated = true), "GalaxySSI-fixture"))
        assertFalse(AgentTimerObservation.provesRemoved(empty.copy(nodes = emptyList()), "GalaxySSI-fixture"))
        assertFalse(AgentTimerObservation.provesRemoved(empty.copy(nodes = empty.nodes +
            node("timer_name_view", "GalaxySSI-fixture")), "GalaxySSI-fixture"))
    }
}
