package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentExecutionPresentationTest {
    @Test
    fun desktopTargetSeparatesExecutorFromComputer() {
        val presentation = AgentExecutionPresentationPolicy.local(
            routeKind = AgentRouteKind.DESKTOP_AGENT,
            targetTitle = "Codex \u00b7 WORKSTATION",
            selectedAgentOrModel = "",
            phase = AgentPhase.EXECUTING,
            currentStep = "Reading files",
            startedAtMillis = 1_000L
        )

        assertEquals("Codex", presentation.executorLabel)
        assertEquals("WORKSTATION", presentation.locationLabelHint)
        assertEquals(AgentExecutionLocationKind.DESKTOP, presentation.locationKind)
        assertTrue(presentation.cancellable)
    }

    @Test
    fun localAndCloudLocationsRemainDistinct() {
        val phone = AgentExecutionPresentationPolicy.local(
            AgentRouteKind.LOCAL_SYSTEM,
            "",
            "",
            AgentPhase.EXECUTING,
            "Reading battery",
            1_000L
        )
        val cloud = AgentExecutionPresentationPolicy.local(
            AgentRouteKind.CLOUD_MODEL,
            "DeepSeek",
            "",
            AgentPhase.WAITING_RESPONSE,
            "Waiting for model",
            1_000L
        )

        assertEquals(AgentExecutionLocationKind.PHONE, phone.locationKind)
        assertEquals("SignalASI", phone.executorLabel)
        assertEquals(AgentExecutionLocationKind.CLOUD, cloud.locationKind)
        assertEquals("DeepSeek", cloud.executorLabel)
    }

    @Test
    fun remoteTerminalStateCannotAdvertiseCancellation() {
        val completed = AgentExecutionPresentationPolicy.remote(
            executorId = "codex",
            executorLabel = "Codex",
            locationKind = "desktop",
            locationName = "WORKSTATION",
            status = "completed",
            currentStep = "",
            startedAtMillis = 1_000L,
            completedAtMillis = 2_000L,
            advertisedCancellable = true
        )

        assertFalse(completed.cancellable)
        assertEquals(AgentPhase.COMPLETED, completed.phase)
    }
}
