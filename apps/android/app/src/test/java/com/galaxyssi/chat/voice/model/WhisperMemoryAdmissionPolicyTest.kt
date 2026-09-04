package com.galaxyssi.chat.voice.model

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WhisperMemoryAdmissionPolicyTest {
    @Test
    fun `large v3 can start with four gibibytes available`() {
        val decision = WhisperMemoryAdmissionPolicy.evaluate(
            profile = WhisperModelCatalog.require("large"),
            availableMemoryBytes = 4L * GIB,
            currentPssBytes = 320L * MIB
        )

        assertTrue(decision.allowed)
    }

    @Test
    fun `large v3 is rejected when actual available memory is below its footprint`() {
        val decision = WhisperMemoryAdmissionPolicy.evaluate(
            profile = WhisperModelCatalog.require("large"),
            availableMemoryBytes = 3L * GIB,
            currentPssBytes = 320L * MIB
        )

        assertFalse(decision.allowed)
    }

    @Test
    fun `android low memory remains a hard stop`() {
        val decision = WhisperMemoryAdmissionPolicy.evaluate(
            profile = WhisperModelCatalog.require("tiny"),
            availableMemoryBytes = 8L * GIB,
            lowMemory = true
        )

        assertFalse(decision.allowed)
    }

    @Test
    fun `loaded model does not reserve its file footprint twice`() {
        val decision = WhisperMemoryAdmissionPolicy.evaluate(
            profile = WhisperModelCatalog.require("large"),
            availableMemoryBytes = 512L * MIB,
            alreadyLoaded = true
        )

        assertTrue(decision.allowed)
    }

    private companion object {
        const val MIB = 1_048_576L
        const val GIB = 1_073_741_824L
    }
}
