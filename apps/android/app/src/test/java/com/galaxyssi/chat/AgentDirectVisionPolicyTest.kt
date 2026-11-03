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
        assertTrue(AgentDirectVisionPolicy.instructionForImageCount(0).isEmpty())
    }

    @Test
    fun considersReadingOrientationBeforeRejectingContent() {
        val instruction = AgentDirectVisionPolicy.instructionForImageCount(1)
        assertTrue(instruction.contains("0, 90, 180 and 270"))
        assertTrue(instruction.contains("metadata says normal"))
        assertTrue(instruction.contains("state the specific uncertainty"))
    }

    @Test
    fun interpretsWholeContentWithoutHardCodingAnAnswerOrUsingPriorGuesses() {
        val instruction = AgentDirectVisionPolicy.instructionForImageCount(2)
        assertTrue(instruction.contains("equations, tables and diagrams as connected content"))
        assertTrue(instruction.contains("answer or solve it"))
        assertTrue(instruction.contains("earlier model guesses as non-evidence"))
        assertTrue(instruction.contains("blank answer to fill in"))
        assertFalse(instruction.contains("1 + 1"))
        assertFalse(instruction.contains("= 2"))
        assertTrue(instruction.contains("Do not search the web when"))
    }
}
