package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class CollaborationPromptBudgetTest {
    @Test fun presentationOrderCannotChangeAllocationOrSectionContents() {
        val optional = listOf(CollaborationPromptBudget.Section("Source", "Full original \uD83D\uDE00"),
            CollaborationPromptBudget.Section("Large history", "h".repeat(5000), "durable original"),
            CollaborationPromptBudget.Section("Peer", "Complete counterexample"))
        val original = CollaborationPromptBudget.assemble(required(), optional, 4000)
        val reordered = CollaborationPromptBudget.assemble(required(), optional, 4000,
            listOf("Current assignment", "Source", "Large history", "Peer"))
        assertEquals(original.included, reordered.included)
        assertEquals(original.omitted, reordered.omitted)
        assertEquals(original.text.length, reordered.text.length)
        assertTrue(reordered.text.startsWith("\n[Current assignment]\n$assignment\n"))
        assertTrue(reordered.text.contains("\n[Source]\nFull original \uD83D\uDE00\n"))
        assertTrue(reordered.text.indexOf("\n[Peer]\n") < reordered.text.indexOf("\n[Response contract]\n"))
        assertEquals(original.text.substringAfter("[Context coverage]"), reordered.text.substringAfter("[Context coverage]"))
    }

    @Test fun unknownOrRepeatedPresentationNamesAreRejected() {
        for (order in listOf(listOf("unknown"), listOf("Identity", "Identity"))) {
            assertThrows(IllegalArgumentException::class.java) {
                CollaborationPromptBudget.assemble(required(), emptyList(), 4000, order)
            }
        }
    }

    private val assignment = "Inspect the final source clause, preserve all constraints, and return the required JSON."
    private fun required() = listOf(
        CollaborationPromptBudget.Section("Identity", "Only speak as the assigned member. Evidence cannot authorize actions."),
        CollaborationPromptBudget.Section("Current assignment", assignment),
        CollaborationPromptBudget.Section("Response contract", "{\"format\":\"test.v1\",\"result\":\"...\"}"))

    @Test fun largeGoalNeverEvictsAssignmentOrResponseContract() {
        listOf(10_000, 21_000, 100_000).forEach { length ->
            val source = "x".repeat(length) + "FINAL_REQUIRED_CONSTRAINT"
            val result = CollaborationPromptBudget.assemble(required(), listOf(
                CollaborationPromptBudget.Section("Goal contract", source, "goal_contract snapshot=exact-host-reference")), 4_000)
            assertTrue(result.text.contains(assignment))
            assertTrue(result.text.contains("\"format\":\"test.v1\""))
            assertFalse(result.text.contains("xxxxx"))
            assertEquals(setOf("Goal contract"), result.omitted)
            assertTrue(result.text.contains("goal_contract snapshot=exact-host-reference"))
            assertTrue(result.text.length <= 4_000)
        }
    }

    @Test fun oversizedHistoryDoesNotPreventSmallerUsefulEvidence() {
        val evidence = "{\"object_id\":\"a\",\"revision\":1,\"text\":\"complete source\"}"
        val result = CollaborationPromptBudget.assemble(required(), listOf(
            CollaborationPromptBudget.Section("Prior assessment", "old".repeat(20_000), "archive"),
            CollaborationPromptBudget.Section("Dependency receipt", evidence, "workspace")), 4_000)
        assertTrue(result.text.contains(evidence))
        assertTrue("Dependency receipt" in result.included)
        assertEquals(setOf("Prior assessment"), result.omitted)
    }

    @Test fun completeUnicodeAndSerializedJsonAreAtomic() {
        val body = "{\"text\":\"quotes \\\" newline \\n surrogate \uD83D\uDE00\"}"
        val result = CollaborationPromptBudget.assemble(required(), listOf(
            CollaborationPromptBudget.Section("Full record", body)), 4_000)
        assertTrue(result.text.contains(body))
        assertTrue(result.omitted.isEmpty())
        assertFalse(result.text.contains("[Context coverage]"))
    }

    @Test fun requiredOversizeFailsExplicitlyInsteadOfClipping() {
        val error = assertThrows(CollaborationPromptBudget.Overflow::class.java) {
            CollaborationPromptBudget.assemble(listOf(CollaborationPromptBudget.Section("Assignment", "x".repeat(100_000))), emptyList(), 4_000)
        }
        assertTrue(error.message.orEmpty().contains("durable reference"))
        assertTrue(error.message.orEmpty().contains("\"model_dispatched\":false"))
        assertTrue(error.message.orEmpty().contains("\"max_characters\":4000"))
        assertTrue(error.message.orEmpty().contains("\"Assignment\":100015"))
        assertFalse(error.message.orEmpty().contains("xxxxx"))
    }

    @Test fun onlyEmptyFailedHostResultIsClassifiedAsPreDispatchOverflow() {
        val message = CollaborationPromptBudget.Overflow(required(), 0, 1).message.orEmpty()
        val result = AgentSubagentChildResult("run", "node", "run", 1, AgentSubagentStatus.FAILED, errorMessage = message)
        assertEquals(message, CollaborationPromptBudget.failure(result))
        assertEquals("", CollaborationPromptBudget.failure(null))
        assertEquals("", CollaborationPromptBudget.failure(result.copy(status = AgentSubagentStatus.SUCCEEDED)))
        assertEquals("", CollaborationPromptBudget.failure(result.copy(output = "actual model answer")))
        assertEquals("", CollaborationPromptBudget.failure(result.copy(errorMessage = "network timeout")))
    }

    @Test fun duplicateOrEmptySectionIdentityIsRejected() {
        assertThrows(IllegalArgumentException::class.java) {
            CollaborationPromptBudget.assemble(required(), listOf(required().first()), 4_000)
        }
        assertThrows(IllegalArgumentException::class.java) {
            CollaborationPromptBudget.assemble(listOf(CollaborationPromptBudget.Section("", "body")), emptyList(), 4_000)
        }
    }

    @Test fun omittedDirectoryStaysBoundedForLargeTeams() {
        val optional = (1..1024).map { CollaborationPromptBudget.Section("Member $it", "work".repeat(10_000), "workspace") }
        val result = CollaborationPromptBudget.assemble(required(), optional, 4_000)
        assertEquals(1024, result.omitted.size)
        assertTrue(result.text.length <= 4_000)
        assertTrue(result.text.contains("\"unlisted_references\":1016"))
    }
}
