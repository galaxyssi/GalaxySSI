package com.galaxyssi.chat

import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.delay
import java.util.concurrent.atomic.AtomicInteger
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationGoalRecruitmentTest {
    private val names = listOf("Turing", "Hopper", "Curie", "Lovelace", "Faraday", "Newton", "Maxwell")
    private fun people() = CollaborationGoalLoop.initial(listOf("lead", "researcher").mapIndexed { index, id ->
        AgentTeamMember("codex", if (index == 0) AgentDeliveryMode.RESPOND else AgentDeliveryMode.OBSERVE,
            instanceId = id, role = if (index == 0) "Coordinator" else "Researcher", context = mapOf(
                "collaboration_group_id" to "group", "collaboration_name" to names[index],
                "collaboration_model_id" to "authorized-model", "collaboration_provider" to "Codex"))
    }, "Develop a verified artifact")
    private fun group() = CollaborationGroup("group", people().map {
        CollaborationMember(it.memberId, it.context.getValue("collaboration_name"), it.agentId, "Codex", modelId = "authorized-model")
    }, "lead")
    private fun vacancy(id: String = "test-gap", role: String = "Independent tester") = JSONObject()
        .put("id", id).put("template_member", "researcher").put("role", role)
        .put("scope", "Independently verify the generated artifact with executable tests")
        .put("reason", "Existing researchers are implementing separate artifacts")
    private fun work(member: String = "recruit:test-gap") = JSONObject().put("id", "verify-v1")
        .put("member", member).put("stage", "VERIFY").put("assignment", "Run independent fixture tests")
    private fun assessment() = JSONObject().put("format", CollaborationGoalLoop.FORMAT).put("summary", "Add an independent tester")
        .put("decision", "continue").put("criteria", JSONArray().put(JSONObject().put("id", "artifact")
            .put("requirement", "Verified artifact").put("status", "open").put("evidence", JSONArray())))
        .put("recruit", JSONArray().put(vacancy())).put("work", JSONArray().put(work())).put("blockers", JSONArray())
    private fun definition() = AgentTeamDefinition("team", "codex", people(), primaryInstanceId = "lead")
    private fun request() = AgentRunRequest("group", "turn", "task", runId = "run", goal = "Develop a verified artifact")

    @Test fun recruitedIdentityInheritsOnlyAuthorizedProviderAndCapabilities() {
        val plan = CollaborationGoalRecruitment.plan(people(), JSONArray().put(vacancy()), JSONArray().put(work()), names)
        assertEquals("", plan.error)
        val added = plan.people.last()
        assertEquals("Curie", added.context["collaboration_name"])
        assertEquals("codex", added.agentId)
        assertEquals("authorized-model", added.context["collaboration_model_id"])
        assertEquals(people().last().requiredCapabilities, added.requiredCapabilities)
        assertEquals("Independent tester", added.role)
        assertEquals("false", added.context["collaboration_receive_results"])
        assertEquals(added.memberId, plan.aliases["recruit:test-gap"])
    }

    @Test fun identicalVacancyOrSameScopeCannotCreateRepeatedPeople() {
        val first = CollaborationGoalRecruitment.plan(people(), JSONArray().put(vacancy()), JSONArray().put(work()), names)
        val repeated = CollaborationGoalRecruitment.plan(first.people, JSONArray().put(vacancy()), JSONArray().put(work()), names)
        assertEquals(first.people, repeated.people)
        val renamed = CollaborationGoalRecruitment.plan(first.people, JSONArray().put(vacancy("other-id")), JSONArray().put(work("recruit:other-id")), names)
        assertEquals(3, renamed.people.size)
        assertEquals(first.aliases.values.first(), renamed.aliases.values.first())
        val invalid = CollaborationGoalRecruitment.plan(first.people, JSONArray().put(vacancy(role = "Different role")), JSONArray().put(work()), names)
        assertTrue(invalid.error.isNotBlank())
        assertEquals(first.people, invalid.people)
    }

    @Test fun laterTaskReusesPersistentMemberEvenWithoutPriorRunMetadata() {
        val first = CollaborationGoalRecruitment.plan(people(), JSONArray().put(vacancy()), JSONArray().put(work()), names)
        val nextRun = first.people.map { it.copy(context = it.context.filterKeys { key ->
            key !in setOf(CollaborationGoalRecruitment.VACANCY, CollaborationGoalRecruitment.SIGNATURE,
                CollaborationGoalRecruitment.TEMPLATE, CollaborationGoalRecruitment.PUBLISHED)
        }) }
        val next = CollaborationGoalRecruitment.plan(nextRun, JSONArray().put(vacancy()), JSONArray().put(work()), names)
        assertEquals("", next.error)
        assertEquals(3, next.people.size)
        assertEquals(first.aliases, next.aliases)
        val edited = nextRun.map { if (it.memberId == first.people.last().memberId) it.copy(role = "User changed role") else it }
        assertTrue(CollaborationGoalRecruitment.plan(edited, JSONArray().put(vacancy()), JSONArray().put(work()), names).error.isNotBlank())
    }

    @Test fun fullDirectoryReturnsReassignmentFeedbackInsteadOfCreatingUnboundedMembers() {
        val full = people() + (2 until CollaborationGroup.MAX_MEMBERS).map { index -> people().last().copy(
            instanceId = "person-$index", context = people().last().context + mapOf(
                CollaborationResearchWorkflow.PERSON to "person-$index", "collaboration_name" to "Member $index")) }
        val plan = CollaborationGoalRecruitment.plan(full, JSONArray().put(vacancy()), JSONArray().put(work()), names)
        assertEquals(1024, plan.people.size)
        assertTrue(plan.error.contains("reassign"))
    }

    @Test fun missingTaskUnknownTemplateAndInvalidAssignmentRecruitNobody() {
        val cases = listOf(
            JSONArray().put(vacancy()) to JSONArray(),
            JSONArray().put(vacancy().put("template_member", "unauthorized-provider")) to JSONArray().put(work()),
            JSONArray().put(vacancy()) to JSONArray().put(work().put("stage", "GRANT_PERMISSION")),
            JSONArray().put(vacancy()) to JSONArray().put(work()).put(work("outsider")))
        cases.forEach { (recruits, jobs) ->
            val plan = CollaborationGoalRecruitment.plan(people(), recruits, jobs, names)
            assertTrue(plan.error.isNotBlank())
            assertEquals(people(), plan.people)
        }
    }

    @Test fun unsupportedFieldsCannotChangeInheritedModelOrAddAuthority() {
        val plan = CollaborationGoalRecruitment.plan(people(), JSONArray().put(vacancy()
            .put("agent_id", "outside-agent").put("model_id", "outside-model").put("permissions", "all")), JSONArray().put(work()), names)
        assertEquals("codex", plan.people.last().agentId)
        assertEquals("authorized-model", plan.people.last().context["collaboration_model_id"])
        assertFalse(plan.people.last().context.containsKey("permissions"))
    }

    @Test fun groupProjectionSurvivesReplayAndPreservesUserRenaming() {
        val recruit = CollaborationGoalRecruitment.plan(people(), JSONArray().put(vacancy()), JSONArray().put(work()), names).people.last()
        val (first, admitted) = CollaborationGoalRecruitment.project(group(), listOf(recruit), names)
        assertEquals(3, first.members.size)
        assertEquals("Curie", admitted[recruit.memberId])
        val edited = first.copy(members = first.members.map { if (it.id == recruit.memberId) it.copy(name = "Faraday") else it })
        val (again, readmitted) = CollaborationGoalRecruitment.project(edited, listOf(recruit), names)
        assertEquals(edited, again)
        assertEquals("Faraday", readmitted[recruit.memberId])
    }

    @Test fun projectionResolvesNameCollisionAndRejectsRemovedOrChangedTemplate() {
        val recruit = CollaborationGoalRecruitment.plan(people(), JSONArray().put(vacancy()), JSONArray().put(work()), names).people.last()
        val concurrentGroup = group().let { it.copy(members = it.members + CollaborationMember("concurrent", "Curie", "deepseek", "DeepSeek")) }
        val (projected, admitted) = CollaborationGoalRecruitment.project(concurrentGroup, listOf(recruit), names)
        assertEquals(4, projected.members.size)
        assertEquals("Lovelace", admitted[recruit.memberId])
        val removed = group().copy(members = group().members.take(1))
        assertTrue(CollaborationGoalRecruitment.project(removed, listOf(recruit), names).second.isEmpty())
        val changed = group().copy(members = group().members.map { it.copy(modelId = "different-model") })
        assertTrue(CollaborationGoalRecruitment.project(changed, listOf(recruit), names).second.isEmpty())
    }

    @Test fun recruitmentAndProjectionAreCheckpointedBeforeRealDispatch() = runBlocking {
        val store = InMemoryAgentTeamExecutionStore { names }
        AgentTeamExecutionRuntime(store).use { runtime ->
            runtime.start(definition(), request()) { AgentSubagentOutput(assessment().toString()) }.await()
            assertTrue(store.advanceGoal("run", "lead", 1000))
            val checkpoint = requireNotNull(store.resumeCheckpoint("run"))
            val recruited = checkpoint.definition.members.first { it.context[CollaborationGoalRecruitment.PUBLISHED] == "false" }
            assertEquals(2, checkpoint.definition.members.count { it.deliveryMode != AgentDeliveryMode.IGNORE })
            assertTrue(store.reconcileGoalRecruits("run", checkpoint.definition.primaryMemberId) {
                CollaborationGoalRecruitment.project(group(), it, names).second
            })
            val ready = requireNotNull(store.resumeCheckpoint("run"))
            assertTrue(ready.definition.members.filter { it.context[CollaborationResearchWorkflow.PERSON] == recruited.memberId }
                .all { it.context[CollaborationGoalRecruitment.PUBLISHED] == "true" })
            var projections = 0
            store.reconcileGoalRecruits("run", ready.definition.primaryMemberId) { projections++; emptyMap() }
            assertEquals(0, projections)
            assertFalse(store.advanceGoal("run", "lead", 2000))
        }
    }

    @Test fun rejectedProjectionRemovesAssignmentsAndLetsCoordinatorReplan() = runBlocking {
        val store = InMemoryAgentTeamExecutionStore { names }
        AgentTeamExecutionRuntime(store).use { runtime ->
            runtime.start(definition(), request()) { AgentSubagentOutput(assessment().toString()) }.await()
            store.advanceGoal("run", "lead", 1000)
            val primary = store.snapshot("run")!!.primaryMemberId
            assertTrue(store.reconcileGoalRecruits("run", primary) { emptyMap() })
            val checkpoint = store.resumeCheckpoint("run")!!
            assertEquals(1, checkpoint.definition.members.count { it.deliveryMode != AgentDeliveryMode.IGNORE })
            assertTrue(checkpoint.definition.members.last().dependsOnAgentIds.isEmpty())
            assertTrue(checkpoint.request.context[CollaborationGoalRecruitment.FEEDBACK].toString().contains("not admitted"))
        }
    }

    @Test fun twentyRecruitsQueueBehindExistingTwoSlotConcurrency() = runBlocking {
        val catalog = names + (0 until 20).map { "Taylor ${('A'.code + it).toChar()}" }
        val store = InMemoryAgentTeamExecutionStore { catalog }
        val plan = assessment().put("recruit", JSONArray((0 until 20).map { vacancy("gap-$it", "Specialist $it") }))
            .put("work", JSONArray((0 until 20).map { work("recruit:gap-$it").put("id", "work-$it") }))
        val active = AtomicInteger()
        val peak = AtomicInteger()
        val calls = AtomicInteger()
        AgentTeamExecutionRuntime(store, AgentSubagentLimits(maxConcurrency = 2)).use { runtime ->
            val worker = AgentTeamMemberWorker {
                if (it.member.deliveryMode == AgentDeliveryMode.RESPOND) AgentSubagentOutput(plan.toString())
                else {
                    calls.incrementAndGet()
                    val current = active.incrementAndGet()
                    peak.updateAndGet { maxOf(it, current) }
                    delay(2)
                    active.decrementAndGet()
                    AgentSubagentOutput("Fixture evidence")
                }
            }
            runtime.start(definition(), request(), worker).await()
            store.advanceGoal("run", "lead", 1000)
            val primary = store.snapshot("run")!!.primaryMemberId
            store.reconcileGoalRecruits("run", primary) { CollaborationGoalRecruitment.project(group(), it, catalog).second }
            runtime.resume(store.resumeCheckpoint("run")!!, worker).await()
            assertEquals(20, calls.get())
            assertEquals(2, peak.get())
        }
    }
}
