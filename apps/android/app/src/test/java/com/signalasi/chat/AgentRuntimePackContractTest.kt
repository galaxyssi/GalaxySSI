package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentRuntimePackContractTest {
    @Test
    fun `Gradle is a trusted optional runtime pack with an explicit capability`() {
        assertTrue("gradle" in AgentOnDeviceRuntimeManager.REQUIRED_PACKS)
        assertEquals(
            setOf("gradle.execute"),
            AgentOnDeviceRuntimeManager.REQUIRED_PACK_CAPABILITIES.getValue("gradle")
        )
    }
}
