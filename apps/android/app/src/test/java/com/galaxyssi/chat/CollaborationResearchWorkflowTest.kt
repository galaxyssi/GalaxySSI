package com.galaxyssi.chat

import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationResearchWorkflowTest {
    private fun team(researchers: Int = 6): AgentTeamDefinition {
        val people = (0..researchers).map { index -> AgentTeamMember(agentId = "codex",
            instanceId = "person-$index", role = if (index == 0) "Coordinator" else "Researcher",
            deliveryMode = if (index == 0) AgentDeliveryMode.RESPOND else AgentDeliveryMode.OBSERVE,
            context = mapOf("collaboration_group_id" to "group", "collaboration_name" to "Person $index")) }
        return AgentTeamDefinition(teamId = "research-team", primaryAgentId = "codex", primaryInstanceId = "person-0",
            members = CollaborationResearchWorkflow.expand(people, "Design a verifiable solution"))
    }
    private fun request() = AgentRunRequest("group", "turn", "task", runId = "research-run", goal = "Design a verifiable solution")
    private fun artifact(summary: String) = JSONObject().put("format", CollaborationResearchArtifact.FORMAT)
        .put("summary", summary).put("candidates", JSONArray()).put("findings", JSONArray()).put("questions", JSONArray())

    @Test fun sixResearchersProduceThreeAlternativesWithoutIncreasingLiveConcurrency() = runBlocking {
        val definition = team()
        assertEquals(34, definition.members.size)
        assertEquals(34, definition.members.map { it.memberId }.distinct().size)
        assertEquals(7, definition.members.map { it.context[CollaborationResearchWorkflow.PERSON] }.distinct().size)
        assertEquals(1, definition.members.count { it.deliveryMode == AgentDeliveryMode.RESPOND })
        assertEquals(definition, requireNotNull(AgentTeamDispatchSpecCodec.decode(
            AgentTeamDispatchSpecCodec.encode(AgentTeamDispatchSpec(definition, "research-run")))).definition)
        val active = AtomicInteger()
        val peak = AtomicInteger()
        val observed = ConcurrentHashMap<String, AgentTeamMemberExecutionContext>()
        val runtime = AgentTeamExecutionRuntime(InMemoryAgentTeamExecutionStore(), AgentSubagentLimits(maxConcurrency = 3))
        try {
            val result = runtime.start(definition, request()) { context ->
                val running = active.incrementAndGet()
                peak.updateAndGet { maxOf(it, running) }
                observed[context.member.memberId] = context
                delay(10)
                active.decrementAndGet()
                AgentSubagentOutput(artifact(context.member.objective).toString())
            }.await()
            assertEquals(AgentTeamExecutionState.SUCCEEDED, result.snapshot.state)
            assertTrue(peak.get() in 2..3)
            definition.members.filter { CollaborationResearchWorkflow.stage(it) == CollaborationResearchStage.EXPLORE }.forEach {
                assertEquals(1, observed.getValue(it.memberId).handoff.dependencies.size)
                assertEquals(CollaborationResearchStage.BRIEF, CollaborationResearchWorkflow.stage(definition.members.single { node ->
                    node.memberId == observed.getValue(it.memberId).handoff.dependencies.single().childId }))
            }
            val validators = definition.members.filter { CollaborationResearchWorkflow.stage(it) == CollaborationResearchStage.VERIFY }
            assertEquals(mapOf("C1" to 2, "C2" to 2, "C3" to 2),
                validators.groupingBy { it.context.getValue(CollaborationResearchWorkflow.CANDIDATE) }.eachCount())
            val final = observed.getValue("person-0").handoff.dependencies
            assertEquals(8, final.size)
            assertTrue(final.all { it.status == AgentSubagentStatus.SUCCEEDED })
        } finally { runtime.close() }
    }

    @Test fun autoKeepsSimpleTasksCheapAndRespectsExplicitMode() {
        val people = (0..2).map { AgentRequestedMember("codex", "Person $it", persistentInstanceId = "p$it", collaborationGroupId = "group") }
        assertFalse(CollaborationResearchWorkflow.enabled("What is 17 times 23?", people))
        assertTrue(CollaborationResearchWorkflow.enabled("Design a better plan", people))
        assertFalse(CollaborationResearchWorkflow.enabled("Design a plan", people.map { it.copy(collaborationWorkflow = "PARALLEL") }))
        assertTrue(CollaborationResearchWorkflow.enabled("Compare these", people.map { it.copy(collaborationWorkflow = "RESEARCH") }))
        assertFalse(CollaborationResearchWorkflow.enabled("Research", people.map { it.copy(collaborationGroupId = "") }))
        assertFalse(CollaborationResearchWorkflow.enabled("Research", people.take(2)))
    }

    @Test fun explicitGroupStartsWithTeamSeedNotHeuristicPhoneExecution() {
        val members = listOf(AgentRequestedMember("codex", "Turing", collaborationGroupId = "group"),
            AgentRequestedMember("deepseek", "Curie", collaborationGroupId = "group"))
        val seed = requireNotNull(CollaborationRoutingPolicy.seed("turn", members))
        assertEquals("codex", seed.parameters["connector_id"])
        assertFalse(seed.isSupervisedProjectConnector())
        assertNull(CollaborationRoutingPolicy.seed("turn", members.map { it.copy(collaborationGroupId = "") }))
        assertNull(CollaborationRoutingPolicy.seed("turn", listOf(members[0], members[1].copy(collaborationGroupId = "other"))))
    }

    @Test fun rolesAndStageIdentitiesAreStableAndResearchPathsDiffer() {
        val first = team()
        assertEquals(first, team())
        val explorations = first.members.filter { CollaborationResearchWorkflow.stage(it) == CollaborationResearchStage.EXPLORE }
        assertEquals(6, explorations.map { it.objective }.distinct().size)
        assertTrue(first.members.all { it.context["collaboration_receive_results"] == "false" })
        assertEquals(59, team(11).members.size)
        assertTrue(first.members.all { isPersistedAgentTeamContextKey(CollaborationResearchWorkflow.STAGE) })
    }

    @Test fun crossReviewIsAssignedToAnotherPersonAndRevisionsReceiveTheCritique() {
        val definition = team()
        val nodes = definition.members.associateBy { it.memberId }
        definition.members.filter { CollaborationResearchWorkflow.stage(it) == CollaborationResearchStage.CHALLENGE }.forEach { review ->
            assertTrue(review.dependsOnAgentIds.map(nodes::getValue).any {
                CollaborationResearchWorkflow.stage(it) == CollaborationResearchStage.EXPLORE &&
                    it.context[CollaborationResearchWorkflow.PERSON] != review.context[CollaborationResearchWorkflow.PERSON]
            })
        }
        definition.members.filter { CollaborationResearchWorkflow.stage(it) == CollaborationResearchStage.REVISE }.forEach { revision ->
            assertTrue(revision.dependsOnAgentIds.map(nodes::getValue).any {
                CollaborationResearchWorkflow.stage(it) == CollaborationResearchStage.CHALLENGE &&
                    it.context[CollaborationResearchWorkflow.PERSON] != revision.context[CollaborationResearchWorkflow.PERSON]
            })
        }
    }

    @Test fun targetedQuestionsAreScopedBoundedAndIdempotent() {
        val definition = team()
        val sender = definition.members.first { CollaborationResearchWorkflow.stage(it) == CollaborationResearchStage.EXPLORE }
        val output = artifact("Finding").put("requests", JSONArray().put(JSONObject()
            .put("to", JSONArray(listOf("person-2", "person-3", "outsider")))
            .put("question", "Can you falsify this?").put("candidate_id", "C1"))).toString()
        val messages = CollaborationDirectedDiscussion.messages(definition, request(), sender, output)
        assertEquals(setOf("person-2", "person-3"), messages.map { it.toInstanceId }.toSet())
        val mailbox = InMemoryAgentTeamMailbox()
        repeat(3) { messages.forEach(mailbox::append) }
        assertEquals(2, mailbox.messages("research-run").size)
        assertTrue(mailbox.messages("research-run", "person-4").isEmpty())
        assertTrue(messages.all { !it.isBroadcast && it.kind == AgentTeamMessageKind.REVIEW })
    }

    @Test fun directedRequestsWaitUntilAfterIndependentExploration() = runBlocking {
        val definition = team(2)
        val mailbox = InMemoryAgentTeamMailbox()
        mailbox.append(AgentTeamMessageEnvelope(teamId = definition.teamId, conversationId = "group", supervisorRunId = "research-run",
            fromInstanceId = "person-1", toInstanceId = "person-2", kind = AgentTeamMessageKind.REVIEW, text = "Private checkpoint question"))
        val runtime = AgentTeamExecutionRuntime(InMemoryAgentTeamExecutionStore(), mailbox = mailbox)
        var received = false
        try {
            runtime.start(definition, request()) { context ->
                val inbox = context.request.context["team_messages"] as List<*>
                if (CollaborationResearchWorkflow.stage(context.member) == CollaborationResearchStage.EXPLORE) assertTrue(inbox.isEmpty())
                if (context.member.context[CollaborationResearchWorkflow.PERSON] == "person-2" &&
                    CollaborationResearchWorkflow.stage(context.member) == CollaborationResearchStage.CHALLENGE) {
                    assertEquals(1, inbox.size); received = true
                }
                AgentSubagentOutput(artifact("Evidence").toString())
            }.await()
            assertTrue(received)
        } finally { runtime.close() }
    }

    @Test fun providerFailureIsEvidenceNotInventedSuccess() = runBlocking {
        val definition = team(2)
        val runtime = AgentTeamExecutionRuntime(InMemoryAgentTeamExecutionStore())
        var finalSawFailure = false
        try {
            val result = runtime.start(definition, request()) { context ->
                if (CollaborationResearchWorkflow.stage(context.member) == CollaborationResearchStage.RECHECK)
                    error("Fixture check could not run")
                if (context.member.deliveryMode == AgentDeliveryMode.RESPOND)
                    finalSawFailure = context.handoff.dependencies.any { it.status == AgentSubagentStatus.FAILED }
                AgentSubagentOutput(artifact("Unverified proposal").toString())
            }.await()
            assertTrue(finalSawFailure)
            assertEquals(AgentTeamExecutionState.COMPLETED_WITH_FAILURES, result.snapshot.state)
        } finally { runtime.close() }
    }

    @Test fun malformedArtifactsArePreservedAsUnverifiedNotes() {
        val raw = "I think this might work; no experiment was run."
        val normalized = CollaborationResearchArtifact.handoff(raw, CollaborationResearchStage.VERIFY)
        val parsed = requireNotNull(CollaborationResearchArtifact.decode(normalized))
        assertTrue(parsed.getBoolean("unstructured"))
        assertEquals(raw, parsed.getString("summary"))
        assertEquals(0, parsed.getJSONArray("findings").length())
        assertEquals(raw, CollaborationResearchArtifact.handoff(raw, CollaborationResearchStage.DELIVER))
    }

    @Test fun groupWorkflowRoundTripsWithoutChangingMemberSettings() {
        val group = CollaborationGroup("group", listOf(CollaborationMember(name = "Turing", agentId = "codex", providerLabel = "Codex")),
            workflow = CollaborationWorkflow.RESEARCH)
        assertEquals(group, CollaborationGroupCodec.decode(CollaborationGroupCodec.encode(group)))
        assertEquals("RESEARCH", group.requested(emptyList()).single().collaborationWorkflow)
    }
}
