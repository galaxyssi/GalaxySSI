package com.signalasi.chat

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Test

class AgentRuntimePackBootPolicyTest {
    @Test
    fun reusesTheLastHealthyPackSetBeforeGuessing() {
        val python = attachment("python-uv", "1", modified = 10L)
        val node = attachment("node-js", "2", modified = 20L)

        assertEquals(
            listOf(python),
            AgentRuntimePackBootPolicy.fallbackAttachments(
                desired = listOf(python, node),
                lastHealthyVersions = mapOf("python-uv" to "1")
            )
        )
    }

    @Test
    fun excludesOnlyTheNewestPackWhenThereIsNoKnownHealthySet() {
        val python = attachment("python-uv", "1", modified = 10L)
        val node = attachment("node-js", "2", modified = 20L)

        assertEquals(
            listOf(python),
            AgentRuntimePackBootPolicy.fallbackAttachments(
                desired = listOf(python, node),
                lastHealthyVersions = emptyMap()
            )
        )
    }

    private fun attachment(id: String, version: String, modified: Long): AgentRuntimePackAttachment {
        val image = File.createTempFile(id, ".img").apply {
            deleteOnExit()
            setLastModified(modified)
        }
        return AgentRuntimePackAttachment(id, version, imageFile = image)
    }
}
