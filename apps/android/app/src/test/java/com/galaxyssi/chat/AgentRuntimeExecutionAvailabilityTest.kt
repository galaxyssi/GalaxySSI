package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class AgentRuntimeExecutionAvailabilityTest {
    @Test
    fun disconnectedRecoverableGuestStillExposesExecutionTool() {
        val availability = AgentOnDeviceRuntimeTools.executionAvailability(
            status(
                backend = AgentOnDeviceRuntimeBackend.QEMU_TCG,
                backendReady = false,
                reason = "Guest bridge is disconnected"
            )
        )

        assertEquals(AgentNativeToolAvailabilityStatus.AVAILABLE, availability.status)
    }

    @Test
    fun missingRuntimePrerequisitesRequireSetup() {
        val availability = AgentOnDeviceRuntimeTools.executionAvailability(
            status(
                backend = AgentOnDeviceRuntimeBackend.NONE,
                backendReady = false,
                reason = "Install the linux-base runtime pack"
            )
        )

        assertEquals(AgentNativeToolAvailabilityStatus.REQUIRES_SETUP, availability.status)
        assertEquals("Install the linux-base runtime pack", availability.reason)
    }

    private fun status(
        backend: AgentOnDeviceRuntimeBackend,
        backendReady: Boolean,
        reason: String
    ) = AgentOnDeviceRuntimeStatus(
        backend = backend,
        backendReady = backendReady,
        reason = reason,
        architecture = "arm64-v8a",
        enginePath = "",
        avfAdvertised = false,
        packs = emptyList()
    )
}
