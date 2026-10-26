package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class CloudVisionPromptPolicyTest {
    @Test fun imageRequestsPreserveLoopContractAndDoNotLoadResearchPolicy() {
        val contract = "Return JSON with CALL_NATIVE_TOOL or ANSWER. Execute on the phone only."
        val result = CloudVisionPromptPolicy.compose(contract, 1,
            { error("Image reading must not load research settings") }, "Use image_annotate for drawing.")
        assertTrue(result.startsWith(contract))
        assertTrue(result.contains("0, 90, 180 and 270"))
        assertTrue(result.contains("Use image_annotate"))
        assertTrue(result.contains("native visual model input"))
    }

    @Test fun textRequestsRetainExistingEvidencePolicyExactly() {
        assertEquals("custom\nresearch", CloudVisionPromptPolicy.compose("custom", 0, { "research" }))
    }

    @Test fun multipleImagesRetainDirectVisionPolicyWithoutHardcodedAnswers() {
        val result = CloudVisionPromptPolicy.compose(CloudVisionPromptPolicy.DEFAULT_PROMPT, 3, { error("unused") })
        assertTrue(result.contains("each attached image"))
        assertTrue(result.contains("specific uncertainty"))
        assertFalse(result.contains("1+1"))
    }

    @Test fun historyOnlyPreservesCurrentQuestionAndToolContractWithoutNewImageInstructions() {
        val contract = "Use phone tools when required; otherwise answer the current question."
        val result = CloudVisionPromptPolicy.compose(contract, 1, { error("unused") },
            "Image editing tools remain available.", currentImageCount = 0)
        assertTrue(result.startsWith(contract))
        assertTrue(result.contains(AgentVisualTurnPolicy.HISTORICAL_CONTEXT))
        assertTrue(result.contains(AgentVisualTurnPolicy.ANSWER_STYLE))
        assertTrue(result.contains("Image editing tools remain available."))
        assertFalse(result.contains("inspect the image twice"))
        assertFalse(result.contains("If only an image is supplied"))
    }
}
