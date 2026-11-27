package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AutoGoalTeamModelReviewTest {
    private val chat = AgentConversation("synthetic-chat", "Transit", 1L, 1L)
    private val goal = "Compare fare caps and service expansion, identify assumptions that reverse the ranking, and recommend one."
    private val inference = LocalModelInferenceResult("", "fixture", "test", false, 1L)
    private val flag = LocalModelWebToolProtocol.TEAM_REVIEW
    private val answer = """{"answer":"Expand service under the stated assumptions.","tool_calls":[],"propose_team_review":true}"""

    @Test fun ordinaryObjectiveNeedsNeitherCommandNorExtraModelCallToCarryAnOptionalProposal() {
        assertNull(AutoGoalTeamCommand.parse(goal))
        assertTrue(allowsModelTeamTurn(chat, goal, false, false))
        assertTrue(flag in LocalModelWebToolProtocol.systemPrompt(emptyList(), offerTeamReview = true))
        assertFalse(flag in LocalModelWebToolProtocol.systemPrompt(emptyList()))
        val proposed = LocalModelWebToolProtocol.decode(answer, inference, offerTeamReview = true)
        val unoffered = LocalModelWebToolProtocol.decode(answer, inference)
        assertEquals("Expand service under the stated assumptions.", proposed.assistantText)
        assertEquals(unoffered.assistantText, proposed.assistantText)
        assertEquals(true, proposed.providerMetadata[flag])
        assertNull(unoffered.providerMetadata[flag])
        assertTrue(proposed.toolCalls.isEmpty())
        val direct = LocalModelWebToolProtocol.decode("""{"answer":"Hello.","tool_calls":[]}""", inference, true)
        assertEquals("Hello.", direct.assistantText)
        assertNull(direct.providerMetadata[flag])
        assertTrue(direct.toolCalls.isEmpty())
    }

    @Test fun onlyTheWholeTypedAnswerCanSuggestReviewAndItCannotNameADestinationOrRunATool() {
        val mixed = answer.replace("[]", """[{"name":"synthetic.write","arguments":{}}]""")
        for (invalid in listOf(mixed, "Example: $answer", "$answer trailing", "x</think>$answer",
            answer.replace("true", "\"true\""), answer.replaceFirst("{", """{"objective":"changed","host":"elsewhere","budget":99,"""))) {
            val response = LocalModelWebToolProtocol.decode(invalid, inference, true)
            assertNull(invalid, response.providerMetadata[flag])
            assertTrue(invalid, response.toolCalls.isEmpty())
        }
        // A real, unrelated ordinary tool decision still follows the original protocol.
        val plain = mixed.replace(""","propose_team_review":true""", "")
        assertEquals("synthetic.write", LocalModelWebToolProtocol.decode(plain, inference, true).toolCalls.single().toolId)
    }

    @Test fun exclusionsDoNotDependOnTheModelsOpinion() {
        for (excluded in listOf(chat.copy(privateMode = true), chat.copy(trackingPaused = true),
            chat.copy(globalTopicKey = "health:synthetic"), chat.copy(mergedIntoConversationId = "other"))) {
            assertFalse(allowsModelTeamTurn(excluded, goal, false, false))
        }
        assertFalse(allowsModelTeamTurn(chat, goal, true, false))
        assertFalse(allowsModelTeamTurn(chat, goal, false, true))
        for (excluded in listOf("Compare my medical records.", "Don't use a team. $goal", "/goal $goal", "x".repeat(4001))) {
            assertFalse(allowsModelTeamTurn(chat, excluded, false, false))
        }
    }

    @Test fun reviewIsOneShotOwnedByTheSubmittingWindowAndInvalidatedAcrossDraftOrLifecycleChanges() {
        val draft = TeamReviewDraft()
        val sent = draft.revision
        draft.bind(sent, chat.id, "turn")
        assertFalse(draft.claim("other", "turn"))
        assertFalse(draft.claim(chat.id, "other"))
        assertTrue(draft.claim(chat.id, "turn"))
        assertFalse(draft.claim(chat.id, "turn"))
        draft.invalidate()
        draft.bind(sent, chat.id, "late")
        assertFalse(draft.claim(chat.id, "late"))
        draft.bind(draft.revision, chat.id, "new")
        draft.invalidate()
        assertFalse(draft.claim(chat.id, "new"))
    }

    @Test fun confirmationPinsTheWholeRouteAndNeverSubstitutesForAManualLock() {
        val local = GoalRoute("local-llm", "test-local", "")
        val cloud = GoalRoute("synthetic", "test-cloud", "fingerprint", "fixture.invalid")
        val manual = AgentModelSelection(AgentModelSelectionMode.MANUAL, cloud.target, cloud.model)
        val routes = listOf(local, cloud, cloud.copy(model = "other"), cloud.copy(host = ""))
        val reviewed = eligibleTeamRoutes(manual, routes).single()
        assertEquals(cloud, reviewed)
        assertFalse(reviewed in eligibleTeamRoutes(manual, listOf(cloud.copy(endpointHash = "changed"))))
        assertTrue(eligibleTeamRoutes(manual, listOf(local)).isEmpty())
        assertEquals(listOf(local, cloud), eligibleTeamRoutes(AgentModelSelection(), listOf(local, cloud)))
    }

    @Test fun neitherNullNorAnotherModelOrEndpointCanClaimTheOriginatingCloudTurn() {
        val draft = TeamReviewDraft()
        val route = GoalRoute("chosen", "chosen-model", "endpoint-digest", "fixture.invalid")
        draft.bind(draft.revision, chat.id, "turn-1", route)
        assertFalse(draft.claim(chat.id, "turn-1"))
        assertFalse(draft.claim(chat.id, "turn-1", route.copy(endpointHash = "changed")))
        assertFalse(draft.claim(chat.id, "turn-1", route.copy(model = "other")))
        assertFalse(draft.claim("other", "turn-1", route))
        assertFalse(draft.claim(chat.id, "turn-2", route))
        assertTrue(draft.claim(chat.id, "turn-1", route))
        assertFalse(draft.claim(chat.id, "turn-1", route))
        draft.bind(draft.revision, chat.id, "local")
        assertFalse(draft.claim(chat.id, "local", route))
        assertTrue(draft.claim(chat.id, "local"))
    }
}
