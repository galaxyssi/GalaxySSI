package com.galaxyssi.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentDirectVisionPolicyTest {
    @Test
    fun imageUsesNativeVisionAndRequiresEvidenceReview() {
        val instruction = AgentDirectVisionPolicy.instructionForMimeTypes(listOf("image/jpeg"))

        assertTrue(instruction.contains("native visual model input"))
        assertTrue(instruction.contains("inspect the image twice"))
        assertTrue(instruction.contains("visible shape, logos, and readable"))
        assertTrue(instruction.contains("unrelated prior"))
        assertFalse(instruction.contains("OCR", ignoreCase = true))
    }

    @Test
    fun nonImageAttachmentDoesNotAddVisionInstructions() {
        assertTrue(
            AgentDirectVisionPolicy.instructionForMimeTypes(listOf("application/pdf")).isEmpty()
        )
    }
}
