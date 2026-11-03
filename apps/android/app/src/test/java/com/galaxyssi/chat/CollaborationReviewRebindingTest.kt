package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class CollaborationReviewRebindingTest {
    @Test fun coordinatorDiscoversLatePrerequisiteAndBindsWithoutRewritingStartingInputs() {
        val workspace = workspace(); publish(workspace)
        val first = prepared(workspace)
        val planner = planner(first)
        val access = CollaborationMilestoneDispatch.access(first, planner)
        val covered = CollaborationMilestoneDispatch.inputs(planner).mapTo(hashSetOf()) { it.getString("token") }
        val empty = workspace.coordinatorUpdates(access, "", covered, setOf("producer", "probe"))
        assertTrue(empty.getBoolean("caught_up_at_read"))
        val probe = author.copy(nodeId = "probe", personId = "peer")
        val data = publish(workspace, "data-v1", access = probe)
        assertNull(workspace.read(access, data.getString("object_id"), 1))
        val page = workspace.coordinatorUpdates(access, empty.getString("next_cursor"), covered, setOf("producer", "probe"))
        val token = page.getJSONArray("milestones").getJSONObject(0).getString("token")
        assertEquals(1, page.getJSONArray("milestones").length())
        val resolved = CollaborationCoordinatorUpdates.withGrants(access, workspace.coordinatorOffered(access))
        assertNotNull(workspace.read(resolved, data.getString("object_id"), 1))
        publish(workspace, "data-v2", data, probe)
        assertNull(workspace.read(resolved, data.getString("object_id"), 2))
        assertEquals(page.toString(), workspace.coordinatorUpdates(access, "", covered, setOf("producer", "probe")).toString())
        val binding = request(first).apply { getJSONArray("inputs").put(JSONObject().put("dependency", "probe")
            .put("uses_milestones", JSONArray().put(token))) }
        val changed = update(returned(first, binding), workspace, setOf("producer", "probe"))
        assertEquals("", changed.request.context[CollaborationLiveGraph.FEEDBACK])
        assertTrue(review(changed).dependsOnAgentIds.isEmpty())
        val savedPlanner = changed.definition.members.single { it.memberId == planner.memberId }
        assertEquals(planner.context[CollaborationMilestoneDispatch.INPUTS], savedPlanner.context[CollaborationMilestoneDispatch.INPUTS])
        assertEquals(planner.context[CollaborationMilestoneDispatch.GRANTS], savedPlanner.context[CollaborationMilestoneDispatch.GRANTS])
        assertEquals(access, CollaborationMilestoneDispatch.access(changed, savedPlanner))
        assertEquals(token, CollaborationCoordinatorUpdates.offered(savedPlanner).single().getString("token"))
        assertFalse(CollaborationCoordinatorUpdates.offered(review(changed)).isNotEmpty())
        assertNull(workspace.read(CollaborationMilestoneDispatch.access(changed, review(changed)), data.getString("object_id"), 2))
        assertEquals(first.request.goal, changed.request.goal)
        assertEquals(first.definition.members.single { it.memberId == "final" }.dependsOnAgentIds,
            changed.definition.members.single { it.memberId == "final" }.dependsOnAgentIds.filterNot { id ->
                changed.definition.members.any { it.memberId == id && CollaborationLiveGraph.planner(it) && it.memberId != planner.memberId }
            }.toSet())
    }

    @Test fun onlyExactActivePlannerCanRequestUpdates() {
        val workspace = workspace(); publish(workspace)
        val first = prepared(workspace)
        val access = CollaborationMilestoneDispatch.access(first, planner(first))
        val checkpoint = AgentTeamExecutionCheckpoint(first.definition, first.request, emptyMap(), 0)
        assertEquals(planner(first), CollaborationCoordinatorUpdates.member(checkpoint, access, AgentTeamUserControl.RUN, false))
        for (bad in listOf(access.copy(runId = "other"), access.copy(turnId = "other"), access.copy(round = 2),
            access.copy(personId = "peer"), access.copy(pinnedReads = emptySet()), access.copy(dependencyNodes = setOf("probe")),
            CollaborationMilestoneDispatch.access(first, review(first)), author)) {
            assertThrows(IllegalArgumentException::class.java) {
                CollaborationCoordinatorUpdates.member(checkpoint, bad, AgentTeamUserControl.RUN, false)
            }
        }
        for (control in listOf(AgentTeamUserControl.PAUSE, AgentTeamUserControl.STOP)) assertThrows(IllegalArgumentException::class.java) {
            CollaborationCoordinatorUpdates.member(checkpoint, access, control, false)
        }
        assertThrows(IllegalArgumentException::class.java) {
            CollaborationCoordinatorUpdates.member(checkpoint, access, AgentTeamUserControl.RUN, true)
        }
        val result = returned(first).events.last().result!!
        assertThrows(IllegalArgumentException::class.java) {
            CollaborationCoordinatorUpdates.member(checkpoint.copy(completed = mapOf(result.childId to result)), access, AgentTeamUserControl.RUN, false)
        }
    }

    private class Rows : CollaborationWorkspaceRows {
        val data = sortedMapOf<String, String>()
        override fun read(key: String) = data[key]
        override fun page(prefix: String, after: String, limit: Int) = data.keys.filter { it.startsWith(prefix) && it > after }.take(limit)
        override fun commit(values: Map<String, String>) { data.putAll(values) }
    }
    private val author = CollaborationWorkspaceAccess("group", "run", "turn", 1, "producer", "author")
    private fun workspace() = CollaborationResearchWorkspace(Rows()).also { it.enrollPublication(author, CollaborationResearchStage.EXECUTE) }
    private fun publish(workspace: CollaborationResearchWorkspace, id: String = "v1", ref: JSONObject? = null,
                        access: CollaborationWorkspaceAccess = author): JSONObject {
        workspace.enrollPublication(access, if (access.nodeId == "probe") CollaborationResearchStage.EXPLORE else CollaborationResearchStage.EXECUTE)
        val item = JSONObject().put("id", "candidate").put("kind", "artifact").put("title", id)
            .put("body", JSONObject().put("content", "candidate $id"))
        ref?.let { item.put("object_id", it.getString("object_id")).put("base_revision", it.getInt("revision")) }
        return workspace.publishMilestone(access, id, JSONObject().put("format", CollaborationResearchArtifact.FORMAT)
            .put("summary", id).put("candidates", JSONArray()).put("findings", JSONArray()).put("workspace", JSONArray().put(item)).toString())
            .getJSONArray("revisions").getJSONObject(0)
    }
    private fun fixture(): AgentTeamExecutionRecord {
        val people = listOf("lead", "author", "peer").map { person -> AgentTeamMember("provider", AgentDeliveryMode.IGNORE,
            instanceId = person, context = mapOf(CollaborationResearchWorkflow.PERSON to person,
                "collaboration_group_id" to "group", CollaborationGoalLoop.ROSTER to "true", CollaborationLiveGraph.ENABLED to "1")) }
        fun work(id: String, person: String, stage: String) = people.single { it.memberId == person }.copy(
            instanceId = id, deliveryMode = AgentDeliveryMode.OBSERVE, objective = "Original $id assignment",
            context = people.single { it.memberId == person }.context + mapOf(CollaborationGoalLoop.ROSTER to "false",
                CollaborationGoalLoop.WORK_ID to id, CollaborationResearchWorkflow.STAGE to stage, CollaborationWorkGraph.POLICY to "success"))
        val producer = work("producer", "author", "EXECUTE")
        val probe = work("probe", "peer", "EXPLORE")
        val review = work("review", "peer", "VERIFY").copy(dependsOnAgentIds = setOf("producer", "probe"),
            context = work("review", "peer", "VERIFY").context + mapOf(CollaborationWorkGraph.INDEPENDENT to "true",
                CollaborationReviewTargets.CONTEXT to "[\"producer\"]"))
        val final = people[0].copy(instanceId = "final", deliveryMode = AgentDeliveryMode.RESPOND,
            dependsOnAgentIds = setOf("producer", "probe", "review"), context = people[0].context + (CollaborationGoalLoop.ROSTER to "false"))
        return AgentTeamExecutionRecord(AgentTeamDefinition("team", "provider", people + producer + probe + review + final, primaryInstanceId = "final"),
            AgentRunRequest("group", "turn", "task", runId = "run", goal = "Original acceptance requirements", createdAtMillis = 1,
                context = mapOf(CollaborationGoalLoop.ROUND to "1", CollaborationGoalLoop.CRITERIA to "original criteria")))
    }
    private fun prepared(workspace: CollaborationResearchWorkspace) = CollaborationLiveGraph.update(fixture(), emptySet(), 1,
        { workspace }, milestoneWorkspace = { workspace })
    private fun planner(record: AgentTeamExecutionRecord) = record.definition.members.last(CollaborationLiveGraph::planner)
    private fun review(record: AgentTeamExecutionRecord) = record.definition.members.single { it.memberId == "review" }
    private fun request(record: AgentTeamExecutionRecord) = JSONObject().put("work_id", "review").put("expected_revision", 0)
        .put("reason", "Pinned candidate is ready; retain independently collected probe input")
        .put("inputs", JSONArray().put(JSONObject().put("dependency", "producer").put("uses_milestones",
            JSONArray().put(CollaborationMilestoneDispatch.inputs(planner(record)).single { it.getString("producer_node") == "producer" }.getString("token")))))
    private fun returned(record: AgentTeamExecutionRecord, vararg requests: JSONObject,
                         field: String = CollaborationReviewRebinding.FIELD, fresh: JSONArray = JSONArray()): AgentTeamExecutionRecord {
        val result = AgentSubagentChildResult("run", planner(record).memberId, "run", 1, AgentSubagentStatus.SUCCEEDED,
            output = JSONObject().put("format", CollaborationLiveGraph.FORMAT).put("summary", "Review exact published version")
                .put("work", fresh).put(field, JSONArray(requests.toList())).toString(),
            startedAtMillis = 1, completedAtMillis = 2)
        return record.copy(events = record.events + AgentSubagentEvent(1, "run", result.childId, AgentSubagentEventKinds.CHILD_SUCCEEDED,
            childStatus = result.status, result = result, timestampMillis = 2))
    }
    private fun update(record: AgentTeamExecutionRecord, workspace: CollaborationResearchWorkspace,
                       admitted: Set<String>? = setOf("producer"), control: AgentTeamUserControl = AgentTeamUserControl.RUN) =
        CollaborationLiveGraph.update(record, setOf(planner(record).memberId), 3, { workspace }, control,
            milestoneWorkspace = { workspace }, admittedIds = admitted)

    @Test fun bindsExactVersionWithoutReleasingIndependentProbeOrChangingGoal() {
        val workspace = workspace(); val ref = publish(workspace)
        val before = prepared(workspace)
        val changed = update(returned(before, request(before)), workspace)
        assertEquals("", changed.request.context[CollaborationLiveGraph.FEEDBACK])
        val member = review(changed)
        assertEquals(setOf("probe"), member.dependsOnAgentIds)
        assertEquals(review(before).objective, member.objective)
        assertEquals("1", member.context[CollaborationReviewRebinding.REVISION])
        assertEquals("[]", member.context[CollaborationReviewTargets.CONTEXT])
        assertEquals("true", member.context[CollaborationWorkGraph.INDEPENDENT])
        assertEquals(before.request.goal, changed.request.goal)
        assertEquals(before.request.context[CollaborationGoalLoop.CRITERIA], changed.request.context[CollaborationGoalLoop.CRITERIA])
        assertEquals(before.definition.members.size, changed.definition.members.size)
        assertEquals(before.definition.members.single { it.memberId == "producer" }, changed.definition.members.single { it.memberId == "producer" })
        val access = CollaborationMilestoneDispatch.access(changed, member)
        assertNotNull(workspace.read(access, ref.getString("object_id"), 1))
        publish(workspace, "v2", ref)
        assertNull(workspace.read(access, ref.getString("object_id"), 2))
        val history = JSONArray(member.context.getValue(CollaborationReviewRebinding.HISTORY)).getJSONObject(0)
        assertEquals(0, history.getInt("previous_revision"))
        assertEquals("producer", history.getJSONArray("replaced_dependencies").getString(0))
        assertEquals(1L, AgentTeamGraphPlan.build(changed.definition, changed.request).children.single { it.childId == "review" }.dependencyRevision)
        assertTrue(CollaborationReviewRebinding.prompt(member)!!.contains("do not claim later versions"))
    }

    @Test fun codecReplayIsIdempotentAndPauseDefersWithoutConsumingThePlan() {
        val workspace = workspace(); publish(workspace)
        val before = prepared(workspace); val response = returned(before, request(before))
        val paused = update(response, workspace, control = AgentTeamUserControl.PAUSE)
        assertEquals(response, paused)
        val changed = update(paused, workspace)
        val codec = Class.forName("com.galaxyssi.chat.AgentTeamExecutionCodec")
        val instance = codec.getDeclaredField("INSTANCE").apply { isAccessible = true }.get(null)
        val encoded = requireNotNull(codec.getDeclaredMethod("encode", List::class.java).apply { isAccessible = true }
            .invoke(instance, listOf(changed))).toString()
        @Suppress("UNCHECKED_CAST")
        val reopened = (codec.getDeclaredMethod("decode", String::class.java).apply { isAccessible = true }
            .invoke(instance, encoded) as List<AgentTeamExecutionRecord>).single()
        assertEquals(changed, reopened)
        assertEquals(changed, update(reopened, workspace))
    }

    @Test fun admittedRunningTerminalAndUnknownAdmissionStateRejectWithoutPartialMutation() {
        val workspace = workspace(); publish(workspace)
        val first = prepared(workspace); val base = returned(first, request(first))
        val cases = listOf(base to setOf("review"), base to null) + listOf(
            AgentSubagentEventKinds.CHILD_ADMITTED to AgentSubagentStatus.QUEUED,
            AgentSubagentEventKinds.CHILD_RUNNING to AgentSubagentStatus.RUNNING,
            AgentSubagentEventKinds.CHILD_SUCCEEDED to AgentSubagentStatus.SUCCEEDED).map { (kind, status) ->
            base.copy(events = base.events + AgentSubagentEvent(2, "run", "review", kind, childStatus = status, timestampMillis = 2)) to emptySet<String>()
        }
        cases.forEach { (record, admissions) ->
            val rejected = update(record, workspace, admissions)
            assertEquals(record.definition, rejected.definition)
            assertTrue(rejected.request.context[CollaborationLiveGraph.FEEDBACK].toString().isNotBlank())
        }
    }

    @Test fun retainedAdmissionStillProtectsReviewAfterLongQueuedHistory(): Unit = runBlocking {
        val workspace = workspace(); publish(workspace)
        val first = prepared(workspace)
        val store = InMemoryAgentTeamExecutionStore().apply {
            candidateWorkspace = { workspace }
            milestoneWorkspace = { workspace }
        }
        store.create(first.definition, first.request)
        var sequence = 0L
        store.append(AgentSubagentEvent(++sequence, "run", "review", AgentSubagentEventKinds.CHILD_ADMITTED,
            childStatus = AgentSubagentStatus.QUEUED, timestampMillis = sequence))
        repeat(InMemoryAgentTeamExecutionStore.MAX_EVENTS_PER_RUN * 2) {
            store.append(AgentSubagentEvent(++sequence, "run", "review", AgentSubagentEventKinds.CHILD_QUEUED,
                childStatus = AgentSubagentStatus.QUEUED, timestampMillis = sequence))
        }
        store.append(returned(first, request(first)).events.last().copy(sequence = ++sequence, timestampMillis = sequence))
        val checkpoint = store.expandResearchGraph("run", "final", setOf(planner(first).memberId), sequence + 1,
            admittedIds = emptySet())!!
        assertEquals(first.definition, checkpoint.definition)
        assertTrue(checkpoint.request.context[CollaborationLiveGraph.FEEDBACK].toString().contains("admitted"))
        assertEquals(setOf("producer", "probe"), checkpoint.definition.members.single { it.memberId == "review" }.dependsOnAgentIds)
    }

    @Test fun staleUnknownSelfReviewAndMismatchedInputsAreRejected() {
        val workspace = workspace(); publish(workspace)
        val first = prepared(workspace)
        val cases = listOf(
            request(first).put("expected_revision", 1), request(first).put("expected_revision", 0.5),
            request(first).put("expected_revision", "0"), request(first).put("work_id", "missing"),
            request(first).put("reason", ""), request(first).put("member", "other"),
            request(first).put("inputs", JSONArray()),
            request(first).apply { getJSONArray("inputs").getJSONObject(0).put("dependency", "probe") },
            request(first).apply { getJSONArray("inputs").getJSONObject(0).put("uses_milestones", JSONArray().put("f".repeat(64))) })
        cases.forEach { bad ->
            val record = returned(first, bad)
            val rejected = update(record, workspace)
            assertEquals(record.definition, rejected.definition)
            assertTrue(rejected.request.context[CollaborationLiveGraph.FEEDBACK].toString().isNotBlank())
        }
        for (key in listOf(CollaborationResearchWorkflow.PERSON, CollaborationWorkGraph.INDEPENDENT, CollaborationCandidateEvolution.TASK)) {
            val record = returned(first.copy(definition = first.definition.copy(members = first.definition.members.map {
                if (it.memberId != "review") it else it.copy(context = it.context + (key to
                    if (key == CollaborationResearchWorkflow.PERSON) "author" else "false"))
            })), request(first))
            assertEquals(record.definition, update(record, workspace).definition)
        }
    }

    @Test fun multipleChangesAreAllOrNothingAndWrongProducerCannotSupplyAnInput() {
        val workspace = workspace(); publish(workspace)
        val first = prepared(workspace)
        val response = returned(first, request(first), request(first))
        assertEquals(response.definition, update(response, workspace).definition)
        val token = CollaborationMilestoneDispatch.inputs(planner(first)).single()
        val corruptPlanner = planner(first).copy(context = planner(first).context + CollaborationMilestoneDispatch.context(
            listOf(JSONObject(token.toString()).put("producer_node", "another-producer"))))
        val wrong = first.copy(definition = first.definition.copy(members = first.definition.members.map {
            if (it.memberId == corruptPlanner.memberId) corruptPlanner else it
        }))
        val record = returned(wrong, request(first))
        assertEquals(record.definition, update(record, workspace).definition)
    }

    @Test fun frozenIndependentDataReplacesOnlyItsWaitAndPreservesExactRoles() {
        val workspace = workspace(); val candidate = publish(workspace)
        val probe = author.copy(nodeId = "probe", personId = "peer")
        val data = publish(workspace, "data-v1", access = probe)
        val first = prepared(workspace)
        val tokens = CollaborationMilestoneDispatch.inputs(planner(first)).associateBy { it.getString("producer_node") }
        val request = request(first).apply { getJSONArray("inputs").put(JSONObject().put("dependency", "probe")
            .put("uses_milestones", JSONArray().put(tokens.getValue("probe").getString("token")))) }
        val changed = update(returned(first, request), workspace, admitted = setOf("producer", "probe"))
        assertEquals("", changed.request.context[CollaborationLiveGraph.FEEDBACK])
        val review = review(changed)
        assertTrue(review.dependsOnAgentIds.isEmpty())
        assertEquals(review(first).objective, review.objective)
        assertEquals(setOf(tokens.getValue("producer").getString("token")), CollaborationReviewTargets.milestones(review))
        assertEquals(2, CollaborationMilestoneDispatch.inputs(review).size)
        val access = CollaborationMilestoneDispatch.access(changed, review)
        assertNotNull(workspace.read(access, candidate.getString("object_id"), 1))
        assertNotNull(workspace.read(access, data.getString("object_id"), 1))
        publish(workspace, "data-v2", data, probe)
        assertNull(workspace.read(access, data.getString("object_id"), 2))
        assertEquals(first.definition.members.filter { it.memberId in setOf("producer", "probe", "final") },
            changed.definition.members.filter { it.memberId in setOf("producer", "probe", "final") })
        val history = JSONArray(review.context.getValue(CollaborationReviewRebinding.HISTORY)).getJSONObject(0)
        assertEquals("prerequisite", history.getJSONObject("input_roles").getString("probe"))
        assertEquals("review_subject", history.getJSONObject("input_roles").getString("producer"))
        val prompt = JSONObject(CollaborationReviewTargets.prompt(review)!!)
        assertEquals(tokens.getValue("probe").getString("token"), prompt.getJSONArray("supporting_milestones").getString(0))
        val inventory = JSONObject(CollaborationLiveGraph.inventory(first.definition, emptyMap())).getJSONArray("items")
        val row = (0 until inventory.length()).map(inventory::getJSONObject).single { it.getString("id") == "review" }
        val waiting = row.getJSONArray("waiting_for")
        val probeWait = (0 until waiting.length()).map(waiting::getJSONObject).single { it.getString("id") == "probe" }
        assertEquals("prerequisite", probeWait.getString("input_role"))
        assertEquals(tokens.getValue("probe").getString("token"), probeWait.getJSONArray("published_milestones").getString(0))
    }

    @Test fun prerequisiteOnlyRebindKeepsCandidateDependencyAndCannotRelabelASubject() {
        val workspace = workspace(); publish(workspace)
        publish(workspace, "data", access = author.copy(nodeId = "probe", personId = "peer"))
        val first = prepared(workspace)
        val token = CollaborationMilestoneDispatch.inputs(planner(first)).single { it.getString("producer_node") == "probe" }.getString("token")
        val request = request(first).apply { getJSONArray("inputs").getJSONObject(0).put("dependency", "probe")
            .put("uses_milestones", JSONArray().put(token)) }
        val changed = update(returned(first, request), workspace)
        assertEquals("", changed.request.context[CollaborationLiveGraph.FEEDBACK])
        assertEquals(setOf("producer"), review(changed).dependsOnAgentIds)
        assertEquals("[\"producer\"]", review(changed).context[CollaborationReviewTargets.CONTEXT])
        assertTrue(CollaborationReviewTargets.milestones(review(changed)).isEmpty())
        val selfReview = first.copy(definition = first.definition.copy(members = first.definition.members.map {
            if (it.memberId == "review") it.copy(context = it.context + (CollaborationReviewTargets.CONTEXT to "[\"producer\",\"probe\"]")) else it
        }))
        val rejected = update(returned(selfReview, request), workspace)
        assertEquals(selfReview.definition, rejected.definition)
        assertTrue(rejected.request.context[CollaborationLiveGraph.FEEDBACK].toString().contains("independent author"))
    }

    @Test fun laterDataPublicationBindsAtANewCheckpointWithoutLosingTheFirstVersion() {
        val workspace = workspace(); publish(workspace)
        val initial = prepared(workspace)
        val first = update(returned(initial, request(initial)), workspace)
        publish(workspace, "data-v1", access = author.copy(nodeId = "probe", personId = "peer"))
        val second = update(first, workspace)
        assertNotEquals(planner(first).memberId, planner(second).memberId)
        val token = CollaborationMilestoneDispatch.inputs(planner(second)).single().getString("token")
        val amendment = JSONObject().put("work_id", "review").put("expected_revision", 1)
            .put("reason", "Frozen probe data now covers the remaining input; its report may continue")
            .put("inputs", JSONArray().put(JSONObject().put("dependency", "probe").put("uses_milestones", JSONArray().put(token))))
        val response = returned(second, amendment)
        val paused = update(response, workspace, control = AgentTeamUserControl.PAUSE)
        assertEquals(response, paused)
        val changed = update(paused, workspace)
        assertEquals("", changed.request.context[CollaborationLiveGraph.FEEDBACK])
        assertTrue(review(changed).dependsOnAgentIds.isEmpty())
        assertEquals("2", review(changed).context[CollaborationReviewRebinding.REVISION])
        assertEquals(2, JSONArray(review(changed).context.getValue(CollaborationReviewRebinding.HISTORY)).length())
        assertEquals(CollaborationReviewTargets.milestones(review(first)), CollaborationReviewTargets.milestones(review(changed)))
        assertEquals(2, CollaborationMilestoneDispatch.inputs(review(changed)).size)
        assertEquals(changed, update(changed, workspace))
    }

    private fun typed(record: AgentTeamExecutionRecord, independent: Boolean = false, ids: Set<String> = setOf("producer")) =
        record.copy(definition = record.definition.copy(members = record.definition.members.map { member ->
            if (member.memberId != "review") member else member.copy(context =
                (if (independent) member.context else member.context - CollaborationReviewTargets.CONTEXT) + mapOf(
                    CollaborationResearchWorkflow.STAGE to "CHALLENGE", CollaborationWorkGraph.INDEPENDENT to independent.toString(),
                    CollaborationDataDependencies.CONTEXT to CollaborationDataDependencies.array(ids.associateWith { "Frozen $it data" }).toString()))
        }))

    @Test fun ordinaryChallengeConsumesPinnedDataWithoutChangingTheGoalOrClaimingIndependentVerification() {
        val workspace = workspace(); val ref = publish(workspace)
        val before = typed(prepared(workspace))
        val changed = update(returned(before, request(before), field = CollaborationReviewRebinding.INPUT_FIELD), workspace)
        assertEquals("", changed.request.context[CollaborationLiveGraph.FEEDBACK])
        val member = review(changed)
        assertEquals(setOf("probe"), member.dependsOnAgentIds)
        assertEquals("CHALLENGE", member.context[CollaborationResearchWorkflow.STAGE])
        assertEquals("false", member.context[CollaborationWorkGraph.INDEPENDENT])
        assertFalse(member.context.containsKey(CollaborationReviewTargets.CONTEXT))
        assertFalse(member.context.containsKey(CollaborationReviewTargets.MILESTONE_CONTEXT))
        assertEquals("[]", member.context[CollaborationDataDependencies.CONTEXT])
        assertEquals(review(before).objective, member.objective)
        assertEquals(before.request.goal, changed.request.goal)
        assertEquals(before.request.context[CollaborationGoalLoop.CRITERIA], changed.request.context[CollaborationGoalLoop.CRITERIA])
        val history = JSONArray(member.context.getValue(CollaborationReviewRebinding.HISTORY)).getJSONObject(0)
        assertEquals("declared_data", history.getString("binding_kind"))
        assertEquals("Frozen producer data", history.getJSONObject("data_requirements").getString("producer"))
        val access = CollaborationMilestoneDispatch.access(changed, member)
        assertNotNull(workspace.read(access, ref.getString("object_id"), 1))
        publish(workspace, "v2", ref)
        assertNull(workspace.read(access, ref.getString("object_id"), 2))
        assertEquals(1L, AgentTeamGraphPlan.build(changed.definition, changed.request).children.single { it.childId == "review" }.dependencyRevision)
    }

    @Test fun bothProtocolsPreserveTypedCompletionDependencies() {
        val workspace = workspace(); publish(workspace)
        for (independent in listOf(false, true)) for (field in listOf(CollaborationReviewRebinding.INPUT_FIELD, CollaborationReviewRebinding.FIELD)) {
            val first = typed(prepared(workspace), independent, emptySet())
            val rejected = update(returned(first, request(first), field = field), workspace)
            assertEquals(first.definition, rejected.definition)
            assertTrue(rejected.request.context[CollaborationLiveGraph.FEEDBACK].toString().isNotBlank())
        }
        val untyped = prepared(workspace)
        assertEquals(untyped.definition, update(returned(untyped, request(untyped), field = CollaborationReviewRebinding.INPUT_FIELD), workspace).definition)
    }

    @Test fun dataBindingRetainsIndependentAuthorshipAndRejectsAdmissionOrInvalidNewWorkAtomically() {
        val workspace = workspace(); publish(workspace)
        val first = typed(prepared(workspace), independent = true)
        val good = returned(first, request(first), field = CollaborationReviewRebinding.INPUT_FIELD)
        assertEquals("true", review(update(good, workspace)).context[CollaborationWorkGraph.INDEPENDENT])
        assertEquals(1, CollaborationReviewTargets.milestones(review(update(good, workspace))).size)
        for (admitted in listOf(null, setOf("review"))) assertEquals(first.definition, update(good, workspace, admitted).definition)
        val invalid = JSONArray().put(JSONObject().put("id", "new").put("member", "missing").put("stage", "EXPLORE").put("assignment", "new"))
        assertEquals(first.definition, update(returned(first, request(first), field = CollaborationReviewRebinding.INPUT_FIELD, fresh = invalid), workspace).definition)
        val self = first.copy(definition = first.definition.copy(members = first.definition.members.map {
            if (it.memberId == "review") it.copy(context = it.context + (CollaborationResearchWorkflow.PERSON to "author")) else it
        }))
        assertEquals(self.definition, update(returned(self, request(self), field = CollaborationReviewRebinding.INPUT_FIELD), workspace).definition)
    }

    @Test fun typedBindingPauseStopReplayAndCrossProtocolDuplicateAreSafe() {
        val workspace = workspace(); publish(workspace)
        val first = typed(prepared(workspace))
        val result = returned(first, request(first), field = CollaborationReviewRebinding.INPUT_FIELD)
        for (control in listOf(AgentTeamUserControl.PAUSE, AgentTeamUserControl.STOP)) assertEquals(result, update(result, workspace, control = control))
        val changed = update(result, workspace)
        assertEquals(changed, update(changed, workspace))
        val raw = JSONObject(result.events.last().result!!.output).put(CollaborationReviewRebinding.FIELD, JSONArray().put(request(first)))
        assertThrows(IllegalArgumentException::class.java) { CollaborationLiveGraph.decode(raw.toString()) }
        assertThrows(IllegalArgumentException::class.java) { CollaborationLiveGraph.decode(raw.put(CollaborationReviewRebinding.INPUT_FIELD, "wrong").toString()) }
    }

    @Test fun liveWorkPersistsDataContractAndCannotRewriteItToUnlockExecution() {
        val workspace = workspace(); publish(workspace)
        val first = prepared(workspace)
        val item = JSONObject().put("id", "ordinary").put("member", "peer").put("stage", "CHALLENGE").put("assignment", "Challenge frozen data")
            .put("depends_on", JSONArray().put("producer").put("probe"))
            .put(CollaborationDataDependencies.FIELD, CollaborationDataDependencies.array(mapOf("producer" to "Frozen data")))
        val changed = update(returned(first, fresh = JSONArray().put(item)), workspace)
        assertEquals("", changed.request.context[CollaborationLiveGraph.FEEDBACK])
        val member = changed.definition.members.single { it.context[CollaborationGoalLoop.WORK_ID] == "ordinary" }
        assertEquals(mapOf("producer" to "Frozen data"), CollaborationDataDependencies.from(member))
        val inventory = JSONObject(CollaborationLiveGraph.inventory(changed.definition, emptyMap())).getJSONArray("items")
        val row = (0 until inventory.length()).map(inventory::getJSONObject).single { it.getString("id") == "ordinary" }
        val waits = row.getJSONArray("waiting_for")
        val kinds = (0 until waits.length()).map(waits::getJSONObject).associate { it.getString("id") to it.getString("dependency_kind") }
        assertEquals(mapOf("producer" to "data", "probe" to "completion"), kinds)
        val rewrite = JSONObject(item.toString()).put(CollaborationDataDependencies.FIELD,
            CollaborationDataDependencies.array(mapOf("producer" to "Frozen data", "probe" to "Also release this")))
        val request = returned(changed, fresh = JSONArray().put(rewrite))
        val unapplied = request.copy(request = request.request.copy(context = request.request.context - CollaborationLiveGraph.APPLIED))
        val rejected = update(unapplied, workspace)
        assertEquals(changed.definition, rejected.definition)
        assertTrue(rejected.request.context[CollaborationLiveGraph.FEEDBACK].toString().contains("Cannot rewrite"))
    }

    private fun correction(record: AgentTeamExecutionRecord) = request(record).apply {
        getJSONArray("inputs").getJSONObject(0)
            .put("requirement", "Frozen measurements and candidate relation for the original challenge")
            .put("completion_not_required_because", "The published measurements are immutable; this check does not touch the producer's apparatus")
    }

    private fun barrier(record: AgentTeamExecutionRecord, id: String) = record.copy(definition = record.definition.copy(
        members = record.definition.members.map { member -> if (member.memberId != "review") member else
            member.copy(context = member.context + (CollaborationCompletionBarriers.CONTEXT to
                CollaborationCompletionBarriers.array(mapOf(id to "Release shared apparatus before verification")).toString())) }))

    @Test fun coordinatorCorrectsSequentialPlanningMistakeAndKeepsResourceBarrier() {
        val workspace = workspace(); val ref = publish(workspace)
        val first = barrier(typed(prepared(workspace), independent = true, ids = emptySet()), "probe")
        val changed = update(returned(first, correction(first), field = CollaborationReviewRebinding.CORRECTION_FIELD), workspace)
        assertEquals("", changed.request.context[CollaborationLiveGraph.FEEDBACK])
        val member = review(changed)
        assertEquals(setOf("probe"), member.dependsOnAgentIds)
        assertEquals(review(first).objective, member.objective)
        assertEquals(review(first).agentId, member.agentId)
        assertEquals("true", member.context[CollaborationWorkGraph.INDEPENDENT])
        assertEquals(CollaborationCompletionBarriers.from(review(first)), CollaborationCompletionBarriers.from(member))
        assertEquals(first.request.goal, changed.request.goal)
        assertEquals(first.request.context[CollaborationGoalLoop.CRITERIA], changed.request.context[CollaborationGoalLoop.CRITERIA])
        assertEquals(first.definition.members.filter { it.memberId != "review" }, changed.definition.members.filter { it.memberId != "review" })
        assertEquals(1L, AgentTeamGraphPlan.build(changed.definition, changed.request).children.single { it.childId == "review" }.dependencyRevision)
        val history = JSONArray(member.context.getValue(CollaborationReviewRebinding.HISTORY)).getJSONObject(0)
        assertEquals("corrected_completion_wait", history.getString("binding_kind"))
        val diagnosis = history.getJSONArray("completion_corrections").getJSONObject(0)
        assertEquals("completion", diagnosis.getString("previous_kind"))
        assertEquals("coordinator_assertion_not_verification", diagnosis.getString("assessment"))
        assertEquals("producer", diagnosis.getString("dependency"))
        assertEquals(changed, update(changed, workspace))
        val access = CollaborationMilestoneDispatch.access(changed, member)
        assertNotNull(workspace.read(access, ref.getString("object_id"), 1))
        publish(workspace, "v2", ref)
        assertNull(workspace.read(access, ref.getString("object_id"), 2))
    }

    @Test fun correctionIsNotASilentFallbackForLegacyRebindingOrARequirementRewrite() {
        val workspace = workspace(); publish(workspace)
        val first = typed(prepared(workspace), ids = emptySet())
        for (field in listOf(CollaborationReviewRebinding.FIELD, CollaborationReviewRebinding.INPUT_FIELD))
            assertEquals(first.definition, update(returned(first, request(first), field = field), workspace).definition)
        val changed = update(returned(first, correction(first), field = CollaborationReviewRebinding.CORRECTION_FIELD), workspace)
        assertEquals("", changed.request.context[CollaborationLiveGraph.FEEDBACK])
        assertEquals("false", review(changed).context[CollaborationWorkGraph.INDEPENDENT])
        val alreadyData = typed(prepared(workspace))
        val rejected = update(returned(alreadyData, correction(alreadyData), field = CollaborationReviewRebinding.CORRECTION_FIELD), workspace)
        assertEquals(alreadyData.definition, rejected.definition)
        assertTrue(rejected.request.context[CollaborationLiveGraph.FEEDBACK].toString().contains("already data-only"))
    }

    @Test fun everyBindingProtocolPreservesExplicitCompletionBarriers() {
        val workspace = workspace(); publish(workspace)
        val first = barrier(prepared(workspace), "producer")
        for (field in CollaborationReviewRebinding.FIELDS) {
            val input = if (field == CollaborationReviewRebinding.CORRECTION_FIELD) correction(first) else request(first)
            val candidate = if (field == CollaborationReviewRebinding.INPUT_FIELD) typed(first) else first
            val rejected = update(returned(candidate, input, field = field), workspace)
            assertEquals(candidate.definition, rejected.definition)
            assertTrue(rejected.request.context[CollaborationLiveGraph.FEEDBACK].toString().contains("protected completion barrier"))
        }
    }

    @Test fun correctionRequiresConcreteDiagnosisExactRevisionAndProducerEvidence() {
        val workspace = workspace(); publish(workspace)
        val first = typed(prepared(workspace), ids = emptySet())
        val bad = listOf(request(first), correction(first).put("expected_revision", 1), correction(first).put("reason", "")) +
            listOf("requirement", "completion_not_required_because").flatMap { key ->
                listOf("", 1, "a".repeat(2001)).map { value -> correction(first).apply { getJSONArray("inputs").getJSONObject(0).put(key, value) } }
            } + listOf(correction(first).apply { getJSONArray("inputs").getJSONObject(0).put("dependency", "probe") },
                correction(first).apply { getJSONArray("inputs").getJSONObject(0).put("uses_milestones", JSONArray().put("f".repeat(64))) })
        bad.forEach { input ->
            val rejected = update(returned(first, input, field = CollaborationReviewRebinding.CORRECTION_FIELD), workspace)
            assertEquals(first.definition, rejected.definition)
            assertTrue(rejected.request.context[CollaborationLiveGraph.FEEDBACK].toString().isNotBlank())
        }
    }

    @Test fun correctionCannotMutateAdmittedOrHostManagedWorkAndIsAtomicWithOtherAdditions() {
        val workspace = workspace(); publish(workspace)
        val first = typed(prepared(workspace), independent = true, ids = emptySet())
        val response = returned(first, correction(first), field = CollaborationReviewRebinding.CORRECTION_FIELD)
        for (admitted in listOf(null, setOf("review"))) assertEquals(first.definition, update(response, workspace, admitted).definition)
        val invalid = JSONArray().put(JSONObject().put("id", "new").put("member", "missing").put("stage", "EXPLORE").put("assignment", "new"))
        assertEquals(first.definition, update(returned(first, correction(first), field = CollaborationReviewRebinding.CORRECTION_FIELD, fresh = invalid), workspace).definition)
        for (key in listOf(CollaborationResearchWorkflow.PERSON, CollaborationCandidateEvolution.TASK)) {
            val protected = first.copy(definition = first.definition.copy(members = first.definition.members.map {
                if (it.memberId != "review") it else it.copy(context = it.context + (key to "author"))
            }))
            assertEquals(protected.definition, update(returned(protected, correction(protected), field = CollaborationReviewRebinding.CORRECTION_FIELD), workspace).definition)
        }
        for (status in listOf(AgentSubagentStatus.RUNNING, AgentSubagentStatus.SUCCEEDED)) {
            val running = response.copy(events = response.events + AgentSubagentEvent(2, "run", "review", AgentSubagentEventKinds.CHILD_RUNNING,
                childStatus = status, timestampMillis = 2))
            assertEquals(first.definition, update(running, workspace).definition)
        }
    }

    @Test fun pausedCorrectionIsDeferredAndDuplicateProtocolsDoNotCommitPartialRevisions() {
        val workspace = workspace(); publish(workspace)
        val first = typed(prepared(workspace), ids = emptySet())
        val response = returned(first, correction(first), field = CollaborationReviewRebinding.CORRECTION_FIELD)
        for (control in listOf(AgentTeamUserControl.PAUSE, AgentTeamUserControl.STOP)) assertEquals(response, update(response, workspace, control = control))
        val raw = JSONObject(response.events.last().result!!.output)
        for (field in listOf(CollaborationReviewRebinding.FIELD, CollaborationReviewRebinding.INPUT_FIELD)) {
            assertThrows(IllegalArgumentException::class.java) {
                CollaborationLiveGraph.decode(JSONObject(raw.toString()).put(field, JSONArray().put(request(first))).toString())
            }
        }
        assertThrows(IllegalArgumentException::class.java) { CollaborationLiveGraph.decode(raw.put(CollaborationReviewRebinding.CORRECTION_FIELD, "invalid").toString()) }
    }

    @Test fun completionBarriersRoundTripRejectConflictsAndAffectWorkIdentity() {
        val item = JSONObject().put("id", "check").put("member", "peer").put("stage", "VERIFY").put("assignment", "Original check")
            .put("depends_on", JSONArray().put("producer").put("probe")).put(CollaborationDataDependencies.FIELD,
                CollaborationDataDependencies.array(mapOf("producer" to "Measurements")))
            .put(CollaborationCompletionBarriers.FIELD, CollaborationCompletionBarriers.array(mapOf("probe" to "Release apparatus")))
        val context = CollaborationDataDependencies.context(item)
        assertEquals(mapOf("probe" to "Release apparatus"), CollaborationCompletionBarriers.read(
            CollaborationDataDependencies.restore(JSONObject().put("depends_on", item.getJSONArray("depends_on")), context)))
        val before = CollaborationTeamOrganization.signature(item)
        assertNotEquals(before, CollaborationTeamOrganization.signature(JSONObject(item.toString()).apply { remove(CollaborationCompletionBarriers.FIELD) }))
        for (bad in listOf(JSONArray().put(JSONObject().put("work_id", "probe").put("reason", "")),
            CollaborationCompletionBarriers.array(mapOf("producer" to "Conflicts with data")),
            CollaborationCompletionBarriers.array(mapOf("missing" to "Unknown dependency")))) {
            assertThrows(IllegalArgumentException::class.java) { CollaborationCompletionBarriers.read(JSONObject(item.toString()).put(CollaborationCompletionBarriers.FIELD, bad)) }
            val graph = CollaborationWorkGraph.compile(listOf(JSONObject(item.toString()).put(CollaborationCompletionBarriers.FIELD, bad)), setOf("producer", "probe"))
            assertTrue(graph.error.isNotBlank())
        }
    }

    @Test fun newLiveWorkPreservesBarriersAndCannotRemoveThemByResubmittingWork() {
        val workspace = workspace(); publish(workspace)
        val first = prepared(workspace)
        val item = JSONObject().put("id", "ordinary").put("member", "peer").put("stage", "CHALLENGE").put("assignment", "Challenge after restoration")
            .put("depends_on", JSONArray().put("producer"))
            .put(CollaborationCompletionBarriers.FIELD, CollaborationCompletionBarriers.array(mapOf("producer" to "Restore apparatus")))
        val changed = update(returned(first, fresh = JSONArray().put(item)), workspace)
        assertEquals("", changed.request.context[CollaborationLiveGraph.FEEDBACK])
        val member = changed.definition.members.single { it.context[CollaborationGoalLoop.WORK_ID] == "ordinary" }
        assertEquals(mapOf("producer" to "Restore apparatus"), CollaborationCompletionBarriers.from(member))
        val inventory = JSONObject(CollaborationLiveGraph.inventory(changed.definition, emptyMap())).getJSONArray("items")
        val row = (0 until inventory.length()).map(inventory::getJSONObject).single { it.getString("id") == "ordinary" }
        assertEquals("Restore apparatus", row.getJSONArray("waiting_for").getJSONObject(0).getString("completion_barrier"))
        val response = returned(changed, fresh = JSONArray().put(JSONObject(item.toString()).apply { remove(CollaborationCompletionBarriers.FIELD) }))
        val rejected = update(response.copy(request = response.request.copy(context = response.request.context - CollaborationLiveGraph.APPLIED)), workspace)
        assertEquals(changed.definition, rejected.definition)
        assertTrue(rejected.request.context[CollaborationLiveGraph.FEEDBACK].toString().contains("Cannot rewrite"))
    }
}
