package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class GlobalConnectorResponseScopeTest {
    private fun response(conversation: String, turn: String = "turn") =
        AgentConnectorResponse(42L, "contact", "reply", conversation, turn)

    @Test fun ordinaryConversationNeverInitializesGlobalExecutors() {
        val forbidden = { error("Ordinary replies must not open global stores") }
        assertFalse(GlobalConnectorResponseScope.consume(response("conversation-uuid"), forbidden, forbidden, forbidden))
    }

    @Test fun scopedRepliesOnlyInvokeTheirOwnerEvenWhenNotConsumed() {
        for (scope in GlobalConnectorResponseScope.entries) {
            val calls = mutableListOf<String>()
            assertFalse(GlobalConnectorResponseScope.consume(response(scope.conversation("owner")),
                { calls += "cognition"; false }, { calls += "autonomous"; false }, { calls += "research"; false }))
            val expected = when (scope) {
                GlobalConnectorResponseScope.COGNITION -> "cognition"
                GlobalConnectorResponseScope.ACTION, GlobalConnectorResponseScope.REVIEW -> "autonomous"
                GlobalConnectorResponseScope.RESEARCH -> "research"
            }
            assertEquals(listOf(expected), calls)
        }
    }

    @Test fun acceptedOwnerPropagatesConsumption() {
        for (scope in GlobalConnectorResponseScope.entries) {
            assertTrue(GlobalConnectorResponseScope.consume(response(scope.conversation("owner")), { true }, { true }, { true }))
        }
    }

    @Test fun blankLegacyScopeRetainsOrderedSourceLookupAndShortCircuit() {
        val calls = mutableListOf<String>()
        assertTrue(GlobalConnectorResponseScope.consume(response(""),
            { calls += "cognition"; false }, { calls += "autonomous"; true }, { error("Already consumed") }))
        assertEquals(listOf("cognition", "autonomous"), calls)
        assertFalse(GlobalConnectorResponseScope.consume(response(""), { false }, { false }, { false }))
    }

    @Test fun malformedOrEmbeddedNamespacesDoNotFallBackToGlobalScanning() {
        val forbidden = { error("Malformed scope must not cause global scanning") }
        for (id in listOf(" ", "global-run:", "global-run: ", "x-global-run:owner", "GLOBAL-RUN:owner",
            "global-runner:owner", "global-unknown:owner", "conversation/global-research:owner")) {
            assertFalse(id, GlobalConnectorResponseScope.consume(response(id), forbidden, forbidden, forbidden))
        }
    }

    @Test fun invalidSourceNeverReachesAnExecutorIncludingLegacy() {
        val forbidden = { error("Missing source") }
        for (source in listOf(0L, -1L)) for (id in listOf("", "global-run:owner")) {
            assertFalse(GlobalConnectorResponseScope.consume(response(id).copy(sourceMessageId = source),
                forbidden, forbidden, forbidden))
        }
    }

    @Test fun explicitOwnerAndTurnMismatchCannotMatchSameSource() {
        for (scope in GlobalConnectorResponseScope.entries) {
            val valid = response(scope.conversation("owner"))
            assertTrue(scope.matches(valid, "owner", "turn"))
            assertFalse(scope.matches(valid, "other-owner", "turn"))
            assertFalse(scope.matches(valid, "owner", "other-turn"))
            for (other in GlobalConnectorResponseScope.entries.filter { it != scope }) {
                assertFalse(other.matches(valid, "owner", "turn"))
            }
        }
    }

    @Test fun absentLegacyFieldsDoNotOverridePresentMismatchedFields() {
        val scope = GlobalConnectorResponseScope.RESEARCH
        assertTrue(scope.matches(response("", ""), "owner", "unit"))
        assertTrue(scope.matches(response(scope.conversation("owner"), ""), "owner", "unit"))
        assertFalse(scope.matches(response("", "wrong"), "owner", "unit"))
        assertFalse(scope.matches(response(scope.conversation("wrong"), ""), "owner", "unit"))
        assertFalse(scope.matches(response(" ", ""), "owner", "unit"))
    }

    @Test fun reviewRevisionAndResearchSynthesisAreExactTurns() {
        assertTrue(GlobalConnectorResponseScope.REVIEW.matches(response("global-replan:run", "revision:3"), "run", "revision:3"))
        assertFalse(GlobalConnectorResponseScope.REVIEW.matches(response("global-replan:run", "revision:2"), "run", "revision:3"))
        assertTrue(GlobalConnectorResponseScope.RESEARCH.matches(response("global-research:task", "task:synthesis"), "task", "task:synthesis"))
        assertFalse(GlobalConnectorResponseScope.RESEARCH.matches(response("global-research:task", "unit"), "task", "task:synthesis"))
    }

    @Test fun producersRejectEmptyOwners() {
        for (scope in GlobalConnectorResponseScope.entries) {
            assertThrows(IllegalArgumentException::class.java) { scope.conversation("") }
            assertThrows(IllegalArgumentException::class.java) { scope.conversation(" ") }
        }
    }
}
