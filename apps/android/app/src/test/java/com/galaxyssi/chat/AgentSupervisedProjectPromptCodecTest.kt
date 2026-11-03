package com.galaxyssi.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentSupervisedProjectPromptCodecTest {
    @Test fun latestHostReceiptSurvivesWholeWhenOldContextIsCompacted() {
        val latest = "- status=COMPLETED; tool=galaxyssi.file.inspect; observation={\"head\":\"" +
            "a".repeat(1_700) + "\",\"required_fact\":\"ACTUAL_OUTCOME\",\"tail\":\"" +
            "z".repeat(1_700) + "\"}\n"
        val tools = "Available phone tools:\n- galaxyssi.file.inspect\n"
        val prompt = "Essential execution contract.\n" + tools +
            AgentSupervisedProjectPromptCodec.DYNAMIC_CONTEXT_HEADER + "User goal: verify the file\n" +
            "Old observation ".repeat(1_500) + latest
        val compact = AgentSupervisedProjectPromptCodec.preserveLatestObservation(prompt, 10_000, latest)
        assertTrue(compact.length <= 10_000)
        assertTrue(compact.contains("Essential execution contract"))
        assertTrue(compact.contains(tools))
        assertTrue(compact.contains("User goal: verify the file"))
        assertTrue(compact.endsWith(latest))
        assertEquals(1, compact.split("ACTUAL_OUTCOME").size - 1)
    }

    @Test fun latestReceiptAndCompleteConversationTransportAreBothPreserved() {
        val conversation = AgentTranscriptStore.GALAXYSSI_CONTEXT_TRANSPORT_HEADER +
            "\n{\"version\":1,\"summary\":\"durable constraint\",\"turns\":[{\"role\":\"user\",\"content\":\"DO_NOT_RESEND\"}]}\n" +
            AgentTranscriptStore.GALAXYSSI_CONTEXT_TRANSPORT_FOOTER
        val latest = "- status=FAILED; tool=galaxyssi.file.patch; observation=STALE_HASH_NOT_WRITTEN\n"
        val prompt = "Execution contract.\nAvailable phone tools:\n- galaxyssi.file.patch\n" +
            AgentSupervisedProjectPromptCodec.DYNAMIC_CONTEXT_HEADER + "User goal: update the original file\n" +
            conversation + "\nOld evidence ".repeat(1_000) + latest
        val compact = AgentSupervisedProjectPromptCodec.preserveLatestObservation(prompt, 8_000, latest)
        assertTrue(compact.contains(conversation))
        assertTrue(compact.endsWith(latest))
        assertTrue(compact.length <= 8_000)
    }

    @Test fun smallPromptIsNotRewrittenAndEmptyEvidenceUsesExistingPolicy() {
        val small = "Complete prompt\n- status=COMPLETED; observation=done\n"
        assertEquals(small, AgentSupervisedProjectPromptCodec.preserveLatestObservation(small, 8_000, "observation=done\n"))
        val large = "ordinary context ".repeat(1_000)
        assertEquals(AgentSupervisedProjectPromptCodec.preserveToolInventory(large, 8_000),
            AgentSupervisedProjectPromptCodec.preserveLatestObservation(large, 8_000, ""))
    }

    @Test(expected = IllegalArgumentException::class)
    fun detachedEvidenceCannotBeAppendedAsIfItWereTheActualLedgerSuffix() {
        AgentSupervisedProjectPromptCodec.preserveLatestObservation("context ".repeat(1_000), 5_000, "invented receipt")
    }

    @Test(expected = IllegalArgumentException::class)
    fun oversizedReceiptIsNotSilentlyTruncatedIntoApparentEvidence() {
        val receipt = "observation ".repeat(1_000)
        AgentSupervisedProjectPromptCodec.preserveLatestObservation("contract" + receipt, 5_000, receipt)
    }

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
        val tools = "Available phone tools:\n- galaxyssi.project.repository.inspect\n- galaxyssi.runtime.execute\n"
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
            append(AgentTranscriptStore.GALAXYSSI_CONTEXT_TRANSPORT_HEADER).append('\n')
            append("{\"version\":1,\"turns\":[{\"role\":\"user\",\"content\":")
            append("\"LATEST_USER_CONSTRAINT\"}]}")
            append('\n').append(AgentTranscriptStore.GALAXYSSI_CONTEXT_TRANSPORT_FOOTER)
        }
        val tools = "Available phone tools:\n- galaxyssi.project.repository.inspect\n- galaxyssi.runtime.execute\n"
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
