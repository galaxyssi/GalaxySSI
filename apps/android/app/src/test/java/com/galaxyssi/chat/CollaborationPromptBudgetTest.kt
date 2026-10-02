package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class CollaborationPromptBudgetTest {
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
        val error = assertThrows(IllegalArgumentException::class.java) {
            CollaborationPromptBudget.assemble(listOf(CollaborationPromptBudget.Section("Assignment", "x".repeat(100_000))), emptyList(), 4_000)
        }
        assertTrue(error.message.orEmpty().contains("durable reference"))
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
