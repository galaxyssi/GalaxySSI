package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentSupervisedProjectPromptEnvelopeTest {
    @Test
    fun `stable contract and tools are separated from current project context`() {
        val prompt = """
            Stable execution contract.
            Available phone tools:
            - galaxyssi.workspace.files.read.text
            ${AgentSupervisedProjectPromptCodec.DYNAMIC_CONTEXT_HEADER}User goal: Update the Android project
            Verified project progress ledger: repository ready
        """.trimIndent()

        val envelope = requireNotNull(AgentSupervisedProjectPromptEnvelope.split(prompt))

        assertTrue(envelope.systemPrompt.contains("Stable execution contract"))
        assertTrue(envelope.systemPrompt.contains("galaxyssi.workspace.files.read.text"))
        assertFalse(envelope.systemPrompt.contains("User goal"))
        assertTrue(envelope.userPrompt.startsWith(AgentSupervisedProjectPromptCodec.DYNAMIC_CONTEXT_HEADER))
        assertTrue(envelope.userPrompt.contains("User goal: Update the Android project"))
        assertTrue(envelope.userPrompt.contains("repository ready"))
    }

    @Test
    fun `repair evidence remains in the dynamic user prompt`() {
        val prompt = """
            Stable execution contract.
            ${AgentSupervisedProjectPromptCodec.DYNAMIC_CONTEXT_HEADER}User goal: Build the project
            The last phone action failed: missing dependency
        """.trimIndent()

        val envelope = requireNotNull(AgentSupervisedProjectPromptEnvelope.split(prompt))

        assertFalse(envelope.systemPrompt.contains("missing dependency"))
        assertTrue(envelope.userPrompt.contains("missing dependency"))
    }

    @Test
    fun `ordinary chat prompt is not rewritten`() {
        assertNull(AgentSupervisedProjectPromptEnvelope.split("Hello"))
    }

    @Test
    fun `split preserves the complete prompt content`() {
        val prompt = "Stable contract\n${AgentSupervisedProjectPromptCodec.DYNAMIC_CONTEXT_HEADER}User goal: test"
        val envelope = requireNotNull(AgentSupervisedProjectPromptEnvelope.split(prompt))

        assertEquals(prompt.trim(), envelope.systemPrompt + "\n" + envelope.userPrompt)
    }
}
