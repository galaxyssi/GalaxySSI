package com.signalasi.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentSupervisedProjectPromptCodecTest {
    @Test
    fun compactSchemaKeepsStructureAndDropsDescriptions() {
        val schema = AgentNativeJsonSchema.objectSchema(
            properties = mapOf(
                "workspace_id" to AgentNativeJsonSchema.string(description = "Long internal description"),
                "files" to AgentNativeJsonSchema.array(
                    AgentNativeJsonSchema.objectSchema(
                        properties = mapOf(
                            "path" to AgentNativeJsonSchema.string(),
                            "text" to AgentNativeJsonSchema.string()
                        ),
                        required = setOf("path", "text"),
                        additionalProperties = false
                    )
                )
            ),
            required = setOf("workspace_id", "files"),
            additionalProperties = false
        )

        val compact = AgentSupervisedProjectPromptCodec.compactInputSchema(schema.document, 240)

        assertTrue(compact.contains("workspace_id!:string"))
        assertTrue(compact.contains("files!:[{path!:string,text!:string}]"))
        assertFalse(compact.contains("Long internal description"))
    }

    @Test
    fun overflowCompactsContextWithoutDroppingToolInventory() {
        val tools = "Available phone tools:\n- signalasi.project.repository.inspect\n- signalasi.runtime.execute\n"
        val prompt = "Essential contract.\n" + "old context ".repeat(1_000) +
            "LATEST_EVIDENCE\n" + tools

        val compact = AgentSupervisedProjectPromptCodec.preserveToolInventory(prompt, 4_000)

        assertTrue(compact.length <= 4_000)
        assertTrue(compact.contains("Essential contract"))
        assertTrue(compact.contains("LATEST_EVIDENCE"))
        assertTrue(compact.endsWith(tools))
    }

    @Test
    fun overflowPreservesCompleteConversationTransportAndLatestEvidence() {
        val conversation = buildString {
            append(AgentTranscriptStore.SIGNALASI_CONTEXT_TRANSPORT_HEADER).append('\n')
            append("{\"version\":1,\"turns\":[{\"role\":\"user\",\"content\":")
            append("\"LATEST_USER_CONSTRAINT\"}]}")
            append('\n').append(AgentTranscriptStore.SIGNALASI_CONTEXT_TRANSPORT_FOOTER)
        }
        val tools = "Available phone tools:\n- signalasi.project.repository.inspect\n- signalasi.runtime.execute\n"
        val prompt = "Essential contract.\n" + "instruction ".repeat(700) +
            "User goal: preserve current work\n" + conversation +
            "\nPrior verified action and observation ledger:\n" + "old evidence ".repeat(400) +
            "LATEST_VERIFIED_EVIDENCE\n" + tools

        val compact = AgentSupervisedProjectPromptCodec.preserveToolInventory(prompt, 4_000)

        assertTrue(compact.length <= 4_000)
        assertTrue(compact.contains("Essential contract"))
        assertTrue(compact.contains("User goal: preserve current work"))
        assertTrue(compact.contains(conversation))
        assertTrue(compact.contains("LATEST_VERIFIED_EVIDENCE"))
        assertTrue(compact.endsWith(tools))
    }
}
