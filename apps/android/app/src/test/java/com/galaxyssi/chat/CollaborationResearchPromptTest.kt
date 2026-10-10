package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationResearchPromptTest {
    @Test fun everyResearchRoleUsesOpaqueRosterIdsIncludingBudgetedPrompts() {
        val misleading = Regex("(?:person|member|roster) UUID", RegexOption.IGNORE_CASE)
        for (stage in CollaborationResearchStage.entries) {
            for (planner in listOf(false, true)) {
                val base = execution("goal ".repeat(10000), stage)
                val current = base.copy(member = base.member.copy(context = base.member.context +
                    (CollaborationLiveGraph.PLANNER to if (planner) "1" else "0")))
                val text = CollaborationResearchPrompt.build(current, descriptor(), emptyMap()).text
                assertTrue("Recipient guidance missing for $stage planner=$planner",
                    text.contains(CollaborationPeerExchangePolicy.MEMBER_ID_INSTRUCTIONS))
                assertFalse("UUID-only guidance for $stage planner=$planner", misleading.containsMatchIn(text))
            }
        }
        for (instructions in listOf(CollaborationLiveGraph.instructions(), CollaborationGoalLoop.instructions(),
            CollaborationLearningAgenda.rules(), CollaborationCandidateEvolution.instructions())) {
            assertTrue(instructions.contains("roster member ID"))
            assertFalse(misleading.containsMatchIn(instructions))
        }
    }

    @Test fun exactPeerContractIsVisibleAndRetainedAsRecoverablePromptMaterial() {
        val base = execution("Compare candidates")
        val selected = base.copy(member = base.member.copy(context = base.member.context +
            (CollaborationPeerExchangePolicy.CONTEXT to "[\"peer-a\",\"peer-b\"]")))
        val materials = CollaborationResearchPrompt.materials(selected, "")
        assertEquals("[\"peer-a\",\"peer-b\"]", materials["Allowed live peer evidence (person IDs; not completion dependencies)"])
        assertTrue(CollaborationResearchArtifact.instructions(CollaborationResearchStage.EXECUTE).contains("mode=peer_updates"))
        assertFalse(CollaborationResearchPrompt.materials(base, "").containsKey("Allowed live peer evidence (person IDs; not completion dependencies)"))
    }

    @Test fun publicationAvailabilityMatchesExecutionPhaseEvenWithOversizedContext() {
        for (stage in CollaborationResearchStage.entries) {
            for (planner in listOf(false, true)) {
                val base = execution("goal ".repeat(10000), stage)
                val execution = base.copy(member = base.member.copy(context = base.member.context +
                    (CollaborationLiveGraph.PLANNER to if (planner) "1" else "0")))
                val text = CollaborationResearchPrompt.build(execution, descriptor(), emptyMap()).text
                if (planner || stage == CollaborationResearchStage.DELIVER) {
                    assertTrue(text.contains("interim_publication=unavailable_for_this_dispatch"))
                    assertTrue(text.contains("Return the required response protocol"))
                    assertFalse(text.contains("interim_publication=enrolled_research_assignment"))
                } else assertTrue(text.contains("interim_publication=enrolled_research_assignment"))
                assertTrue(text.length <= CollaborationResearchPrompt.MAX_CHARACTERS)
            }
        }
        val base = execution("Candidate transition")
        val candidate = base.copy(member = base.member.copy(context = base.member.context +
            (CollaborationCandidateEvolution.TASK to "{}")))
        assertTrue(CollaborationPublicationCapability.instructions(candidate).contains("interim_publication=final_contract_only"))
    }

    @Test fun currentPeerEvidenceIsNotDisplacedByOlderBookkeeping() {
        val execution = execution("Find a method that corrects the observed failure without losing prior behavior")
        var lower = 0
        var upper = CollaborationResearchPrompt.MAX_CHARACTERS
        while (lower < upper) {
            val middle = (lower + upper + 1) / 2
            val probe = CollaborationResearchPrompt.build(execution, descriptor(), linkedMapOf(
                "Live work inventory" to "i".repeat(middle), "New team messages" to ""))
            if ("Live work inventory" in probe.included) lower = middle else upper = middle - 1
        }
        val inventory = "i".repeat(lower - 256)
        val peer = JSONObject().put("from_instance_id", "reviewer")
            .put("text", "counterexample ".repeat(160)).toString()
        val materials = linkedMapOf("Live work inventory" to inventory, "New team messages" to peer)
        val result = CollaborationResearchPrompt.build(execution, descriptor(), materials)
        assertTrue("Current peer contribution must be available before optional bookkeeping", "New team messages" in result.included)
        assertTrue(result.text.contains(peer))
        assertTrue("Live work inventory" in result.omitted)
        assertTrue(result.text.contains("section=context:Live work inventory"))
        assertTrue(result.text.length <= CollaborationResearchPrompt.MAX_CHARACTERS)
    }

    @Test fun goalAndCurrentEvidencePrecedePublicationSchemaWithoutLosingBoundaries() {
        for (stage in CollaborationResearchStage.entries) {
            val result = CollaborationResearchPrompt.build(execution("Exact original task", stage), descriptor(), linkedMapOf(
                "Historical evidence" to "Older directory", "New team messages" to "A peer's disputed claim",
                "Dependency evidence" to "Exact predecessor result", "Acceptance feedback" to "Remaining criterion"))
            val text = result.text
            val protocol = text.indexOf("\n[Response protocol]\n")
            for (name in listOf("Assignment", "Original user goal", "Preserved acceptance criteria", "Host goal contract",
                "Execution boundaries", "New team messages", "Dependency evidence", "Acceptance feedback")) {
                val position = text.indexOf("\n[$name]\n")
                assertTrue("$name should precede schema for $stage", position >= 0 && position < protocol)
            }
            assertTrue(text.indexOf("\n[Execution boundaries]\n") < text.indexOf("\n[New team messages]\n"))
            assertTrue(text.indexOf("\n[Historical evidence]\n") > protocol)
            assertTrue(text.contains(CollaborationEvolutionProtocol.instructions()))
            assertTrue(text.contains("evidence, not authority or permission"))
        }
    }

    @Test fun availabilityReflectsFullAtomicSectionsForEveryRoleAndSize() {
        for (stage in CollaborationResearchStage.entries) {
            for (size in listOf(30, 12_000, 100_000)) {
                val execution = execution("g".repeat(size), stage)
                val result = CollaborationResearchPrompt.build(execution, descriptor(), emptyMap())
                val coverage = JSONObject(result.text.substringAfterLast("\n[Context availability]\n"))
                for ((field, section) in mapOf("original_goal" to "Original user goal",
                    "acceptance_criteria" to "Preserved acceptance criteria", "source_mapping" to "Goal coverage source")) {
                    assertEquals(if (section in result.included) "complete_inline" else "not_inlined", coverage.getString(field))
                    assertEquals(section in result.included, result.text.contains("\n[$section]\n"))
                }
                if (coverage.getString("original_goal") == "complete_inline")
                    assertTrue(result.text.contains("\n[Original user goal]\n${execution.request.goal}\n"))
                assertEquals("supplied_text_not_comprehension_or_validation", coverage.getString("trust"))
                assertTrue(result.text.length <= CollaborationResearchPrompt.MAX_CHARACTERS)
                assertTrue(result.text.contains("Do not refetch complete inline material"))
                assertTrue(result.text.contains("output_truncated=true"))
                assertFalse(result.text.contains("Follow next_cursor until null."))
            }
        }
    }

    @Test fun availabilityNeverPretendsLargeOmittedCriteriaWereSupplied() {
        val base = execution("Short original goal")
        val criteria = JSONArray().put(JSONObject().put("id", "criterion").put("requirement", "full requirement ".repeat(5000))
            .put("status", "open").put("evidence", JSONArray())).toString()
        val execution = base.copy(request = base.request.copy(context = base.request.context + (CollaborationGoalLoop.CRITERIA to criteria)))
        val result = CollaborationResearchPrompt.build(execution, descriptor(), emptyMap())
        val coverage = JSONObject(result.text.substringAfterLast("\n[Context availability]\n"))
        assertEquals("complete_inline", coverage.getString("original_goal"))
        assertEquals("not_inlined", coverage.getString("acceptance_criteria"))
        assertTrue("Preserved acceptance criteria" in result.omitted)
        assertFalse(result.text.contains(criteria))
        assertTrue(result.text.contains("read its pages before planning or certifying coverage"))
    }

    @Test fun recoveredAvailabilityDoesNotRecordDeliveryOrRefreshContext() {
        val rows = MemoryRows()
        val store = CollaborationGoalContractStore(rows, { true })
        val execution = execution("Complete goal with the original constraints")
        CollaborationResearchPrompt.prepare(execution, store) { "Original dependency material" }
        val frozen = rows.values.toMap()
        val recovered = CollaborationResearchPrompt.prepare(execution, store) { error("Do not refresh") }
        val coverage = JSONObject(recovered.substringAfterLast("\n[Context availability]\n"))
        assertEquals("complete_inline", coverage.getString("original_goal"))
        assertEquals("complete_inline", coverage.getString("acceptance_criteria"))
        assertEquals(frozen, rows.values)
        assertFalse(recovered.contains("Original dependency material"))
        val access = CollaborationWorkspaceAccess.from(execution)
        val delivery = store.delivery(access, store.lookup(access).getString("snapshot_id"))
        assertEquals(0, delivery.getInt("delivered_page_count"))
        assertFalse(delivery.getBoolean("all_pages_delivered"))
    }

    @Test fun initialAcceptanceStateCannotBeOmittedWithLargeHistoryOrDuringRecovery() {
        val execution = execution("goal ".repeat(10000), CollaborationResearchStage.DELIVER)
        val store = CollaborationGoalContractStore(MemoryRows(), { true })
        val first = CollaborationResearchPrompt.prepare(execution, store) { "history ".repeat(10000) }
        val restored = CollaborationResearchPrompt.prepare(execution, store) { error("Use preserved snapshot") }
        for (text in listOf(first, restored)) {
            assertTrue(text.contains("acceptance_contract_state=initial_criteria_pending"))
            assertTrue(text.contains("not a damaged contract"))
        }
    }

    @Test fun productionDescriptorAndFullMaterialDirectoryFitEveryRole() {
        for (stage in CollaborationResearchStage.entries) {
            val base = execution("original goal ".repeat(8000), stage)
            val metadata = listOf("collaboration_research_live_inventory", "collaboration_research_roster",
                "collaboration_research_previous_round", CollaborationGoalLoop.PREVIOUS,
                CollaborationGoalLoop.ACCEPTANCE_FEEDBACK, CollaborationGoalLoop.FINISHED_WORK,
                CollaborationGoalRecruitment.FEEDBACK, CollaborationResourceRecovery.FEEDBACK,
                CollaborationWorkGraph.FEEDBACK, CollaborationLiveGraph.FEEDBACK,
                CollaborationCandidateEvolution.FEEDBACK).associateWith { "complete evidence ".repeat(1000) }
            val request = base.copy(request = base.request.copy(context = base.request.context + metadata))
            for (planner in listOf(false, true)) {
                val assigned = if (planner) request.copy(member = request.member.copy(context = request.member.context +
                    (CollaborationLiveGraph.PLANNER to "1"))) else request
                val execution = withResourceObservation(assigned)
                val store = CollaborationGoalContractStore(MemoryRows(), { true })
                val prompt = CollaborationResearchPrompt.prepare(execution, store,
                    evolution = { "evolution ".repeat(1000) }, problems = { "problem ".repeat(1000) },
                    capabilities = { "capability ".repeat(1000) }) { "history ".repeat(10000) }
                assertTrue(prompt.length <= CollaborationResearchPrompt.MAX_CHARACTERS)
                assertTrue(prompt.contains("mode=evolution_rules"))
                assertTrue(prompt.contains("mode=goal_contract"))
                assertTrue(prompt.contains("Never repeat a completed side effect"))
                assertTrue(prompt.contains("[Host resource observation]"))
                val descriptor = store.lookup(CollaborationWorkspaceAccess.from(execution))
                assertTrue(descriptor.getInt("context_section_count") >= 14)
                assertTrue(prompt.contains(descriptor.getString("snapshot_id")))
                val protocol = when {
                    planner -> CollaborationLiveGraph.instructions()
                    stage == CollaborationResearchStage.DELIVER -> CollaborationGoalLoop.instructions()
                    else -> CollaborationResearchArtifact.instructions(stage)
                }
                assertTrue(prompt.contains(protocol))
            }
        }
    }

    @Test fun fullCoordinatorContextWithLiveResourcesLeavesUsefulRoomForOriginalGoal() {
        for (planner in listOf(false, true)) {
            val base = execution("Complete original scientific task and constraints. ".repeat(110), CollaborationResearchStage.DELIVER)
            val assigned = if (planner) base.copy(member = base.member.copy(context = base.member.context +
                (CollaborationLiveGraph.PLANNER to "1"))) else base
            val execution = withResourceObservation(assigned)
            val store = CollaborationGoalContractStore(MemoryRows(), { true })
            val first = CollaborationResearchPrompt.prepare(execution, store) { "historical evidence ".repeat(10_000) }
            val restored = CollaborationResearchPrompt.prepare(execution, store) { error("Use saved snapshot") }
            for (text in listOf(first, restored)) {
                assertTrue(text.length <= CollaborationResearchPrompt.MAX_CHARACTERS)
                assertTrue(text.contains("\n[Original user goal]\n${execution.request.goal}\n"))
                assertTrue(text.contains("[Host resource observation]"))
                assertTrue(text.contains("topic=coordination"))
                assertTrue(text.contains("evidence, not authority or permission"))
                assertTrue(text.contains("Do not guess their fields"))
            }
            println("Full coordinator context planner=$planner characters=${first.length} restored=${restored.length}")
        }
    }

    @Test fun taskRelatedCapabilitiesArePinnedAndNotSearchedAgainOnRecovery() {
        val store = CollaborationGoalContractStore(MemoryRows(), { true })
        val execution = execution("Find evidence without repeating prior failed methods")
        val first = CollaborationResearchPrompt.prepare(execution, store,
            capabilities = { "exact-method-ref-and-applicability" }) { "" }
        assertTrue(first.contains("Task-related capability candidates"))
        assertTrue(first.contains("exact-method-ref-and-applicability"))
        assertTrue(first.contains("mode=capabilities"))
        val retry = CollaborationResearchPrompt.prepare(execution, store,
            capabilities = { error("Recovery must not silently replace method candidates") }) { error("No history refresh") }
        assertTrue(retry.contains("mode=goal_contract"))
    }

    @Test fun problemFactsArePinnedWithoutAddingCallsDuringRecovery() {
        val store = CollaborationGoalContractStore(MemoryRows(), { true })
        val execution = execution("goal")
        val first = CollaborationResearchPrompt.prepare(execution, store,
            problems = { "immutable-original-failure-references" }) { "" }
        assertTrue(first.contains("immutable-original-failure-references"))
        assertTrue(first.contains("mode=problems"))
        val restored = CollaborationResearchPrompt.prepare(execution, store,
            problems = { error("Recovered dispatch must not rescan problems") }) { error("No history refresh") }
        assertTrue(restored.contains("mode=goal_contract"))
    }

    @Test fun everyResearchRoleGetsInnovationPolicyWithoutInliningLargeSchemas() {
        for (stage in CollaborationResearchStage.entries) {
            val result = CollaborationResearchPrompt.build(execution("goal", stage), descriptor(), emptyMap())
            assertTrue(result.text.contains(CollaborationEvolutionProtocol.instructions()))
            assertTrue(result.text.contains("mode=evolution_rules"))
            assertFalse(result.text.contains("galaxyssi.experiment-measurements.v1"))
            assertTrue(result.text.length <= CollaborationResearchPrompt.MAX_CHARACTERS)
        }
    }

    @Test fun evolutionDirectoryIsPinnedAndNotRequeriedOnRecovery() {
        val store = CollaborationGoalContractStore(MemoryRows(), { true })
        val execution = execution("goal")
        val first = CollaborationResearchPrompt.prepare(execution, store, evolution = { "saved exact learning references" }) { "" }
        assertTrue(first.contains("saved exact learning references"))
        val restored = CollaborationResearchPrompt.prepare(execution, store, evolution = { error("Must not refresh on retry") }) { "" }
        assertTrue(restored.contains("mode=goal_contract"))
    }

    @Test fun longGoalsNeverDisplaceCurrentAssignmentOrResponseProtocol() {
        for (size in listOf(10_000, 21_000, 100_000)) {
            val execution = execution("g".repeat(size))
            val result = CollaborationResearchPrompt.build(execution, descriptor(), emptyMap())
            assertTrue(result.text.length <= CollaborationResearchPrompt.MAX_CHARACTERS)
            assertTrue(result.text.contains("objective=Review the original evidence and propose a discriminating test."))
            assertTrue(result.text.contains(CollaborationResearchArtifact.FORMAT))
            assertTrue(result.text.contains("mode=goal_contract"))
            assertTrue(result.text.contains("Never repeat a completed side effect"))
            if ("Original user goal" in result.included) assertTrue(result.text.contains(execution.request.goal))
            else assertTrue("Original user goal" in result.omitted)
        }
    }

    @Test fun coordinatorKeepsFullCompletionContractUnderLargeContext() {
        val execution = execution("g".repeat(100_000), CollaborationResearchStage.DELIVER)
        val materials = mapOf("Prior assessment" to "a".repeat(120_000), "Historical evidence" to "h".repeat(50_000))
        val result = CollaborationResearchPrompt.build(execution, descriptor(), materials)
        assertTrue(result.text.contains(CollaborationGoalLoop.instructions()))
        assertFalse(result.text.contains("a".repeat(120_000)))
        assertTrue(result.omitted.containsAll(materials.keys))
        assertTrue(result.text.contains("omitted_sections"))
    }

    @Test fun livePlannerContractIsNotReplacedByCompletionContract() {
        val base = execution("goal")
        val execution = base.copy(member = base.member.copy(context = base.member.context +
            (CollaborationLiveGraph.PLANNER to "1")))
        assertTrue(CollaborationLiveGraph.planner(execution.member))
        val result = CollaborationResearchPrompt.build(execution, descriptor(), emptyMap())
        assertTrue(result.text.contains(CollaborationLiveGraph.instructions()))
        assertFalse(result.text.contains(CollaborationGoalLoop.instructions()))
    }

    @Test fun materialsKeepFullAssessmentsRostersAndStructuredMessages() {
        val roster = JSONArray((1..1024).map { JSONObject().put("id", "person-$it").put("role", "independent reviewer") }).toString()
        val assessment = JSONObject().put("original", "x".repeat(100_000)).toString()
        val messages = listOf(mapOf("from_instance_id" to "person-1", "text" to "quoted \"text\"\n\u4E2D\u6587 \uD83D\uDE00"))
        val base = execution("goal")
        val execution = base.copy(request = base.request.copy(context = base.request.context + mapOf(
            "collaboration_research_roster" to roster, CollaborationGoalLoop.PREVIOUS to assessment, "team_messages" to messages)))
        val materials = CollaborationResearchPrompt.materials(execution, "original history")
        assertEquals(roster, materials["Member roster"])
        assertEquals(assessment, materials["Prior assessment"])
        assertEquals(messages.first()["text"], JSONArray(materials.getValue("New team messages")).getJSONObject(0).getString("text"))
        val result = CollaborationResearchPrompt.build(execution, descriptor(), materials)
        assertTrue("Member roster" in result.omitted)
        assertTrue("Prior assessment" in result.omitted)
        assertTrue(result.text.contains("section=context:Member roster"))
    }

    @Test fun partialDependencyOutputIsExplicitAndKeepsItsExactNode() {
        val base = execution("goal")
        val execution = base.copy(handoff = base.handoff.copy(dependencies = listOf(AgentSubagentDependencyHandoff(
            childId = "exact-node", status = AgentSubagentStatus.SUCCEEDED, output = "original excerpt",
            outputTruncated = true, provenance = AgentSubagentProvenance()))))
        val material = JSONArray(CollaborationResearchPrompt.materials(execution, "").getValue("Dependency evidence")).getJSONObject(0)
        assertEquals("exact-node", material.getString("node_id"))
        assertTrue(material.getBoolean("output_truncated"))
        assertEquals("original excerpt", material.getString("output"))
    }

    @Test fun resourceFeedbackIsPinnedAndRecallableWhenItDoesNotFitThePrompt() {
        val base = execution("Original goal")
        val feedback = "host resource feedback ".repeat(6000)
        val execution = base.copy(request = base.request.copy(context = base.request.context +
            (CollaborationResourceRecovery.FEEDBACK to feedback)))
        val rows = MemoryRows()
        val store = CollaborationGoalContractStore(rows, { true })
        val materials = CollaborationResearchPrompt.materials(execution, "")
        assertEquals(feedback, materials["Resource resolution feedback"])
        val first = CollaborationResearchPrompt.prepare(execution, store) { "" }
        val recoveredStore = CollaborationGoalContractStore(rows, { true })
        val restored = CollaborationResearchPrompt.prepare(execution, recoveredStore) { error("Must use pinned context") }
        assertTrue(first.contains("section=context:Resource resolution feedback"))
        assertTrue(restored.contains("Resource resolution feedback"))
        assertTrue(restored.contains("mode=goal_contract"))
        val readBack = StringBuilder()
        val access = CollaborationWorkspaceAccess.from(execution)
        var cursor = ""
        do {
            val page = recoveredStore.readSection(access, "context:Resource resolution feedback", cursor)
            val fragments = page.getJSONArray("fragments")
            repeat(fragments.length()) { index ->
                val fragment = fragments.getJSONObject(index)
                if (fragment.optString("kind") == "context" && fragment.optString("id") == "Resource resolution feedback")
                    readBack.append(fragment.getString("text"))
            }
            cursor = page.optString("next_cursor").takeUnless { page.isNull("next_cursor") }.orEmpty()
        } while (cursor.isNotEmpty())
        assertEquals(feedback, readBack.toString())
    }

    @Test fun missingDurableSnapshotFailsBeforeAResearchPromptCanBeDispatched() {
        assertTrue(runCatching {
            CollaborationResearchPrompt.build(execution("goal"), JSONObject().put("status", "rejected"), emptyMap())
        }.exceptionOrNull() is IllegalArgumentException)
    }

    @Test fun prepareRejectsCorruptCriteriaBeforeReadingHistoryOrPublishingAnyContract() {
        for (raw in listOf("not-json", "[] trailing", "[7]", "[{\"id\":\"c\"}]")) {
            val rows = MemoryRows()
            val store = CollaborationGoalContractStore(rows, { true })
            val base = execution("Original goal")
            val execution = base.copy(request = base.request.copy(context = base.request.context +
                (CollaborationGoalLoop.CRITERIA to raw)))
            val error = runCatching {
                CollaborationResearchPrompt.prepare(execution, store) { error("History must not be read under corrupt criteria") }
            }.exceptionOrNull()
            assertEquals(CollaborationGoalLoop.CONTRACT_RECOVERY_REQUIRED, error?.message)
            assertTrue(rows.values.isEmpty())
            assertEquals(raw, execution.request.context[CollaborationGoalLoop.CRITERIA])
        }
    }

    @Test fun preparePreservesPinnedSnapshotOnRetryAndRejectsMutableStatusOrEvidence() {
        val rows = MemoryRows()
        val store = CollaborationGoalContractStore(rows, { true })
        val base = execution("Original goal")
        val criteria = JSONArray().put(JSONObject().put("id", "c").put("requirement", "Original goal")
            .put("status", "open").put("evidence", JSONArray()))
        val execution = base.copy(request = base.request.copy(context = base.request.context +
            (CollaborationGoalLoop.CRITERIA to criteria.toString())))
        val first = CollaborationResearchPrompt.prepare(execution, store) { "Exact historical context" }
        val access = CollaborationWorkspaceAccess.from(execution)
        val pin = store.lookup(access).getString("snapshot_id")
        val retry = CollaborationResearchPrompt.prepare(execution, store) { error("A recovered dispatch must keep its original context") }
        assertTrue(first.contains(pin))
        assertTrue(retry.contains(pin))
        val originalRows = rows.values.toMap()
        criteria.getJSONObject(0).put("status", "met").put("evidence", JSONArray().put("different evidence"))
        val changed = execution.copy(request = execution.request.copy(context = execution.request.context +
            (CollaborationGoalLoop.CRITERIA to criteria.toString())))
        assertTrue(runCatching { CollaborationResearchPrompt.prepare(changed, store) { "new history" } }
            .exceptionOrNull() is IllegalArgumentException)
        assertEquals(originalRows, rows.values)
        assertEquals(pin, store.lookup(access).getString("snapshot_id"))
    }

    private class MemoryRows : CollaborationGoalContractRows {
        val values = linkedMapOf<String, String>()
        override fun read(key: String) = values[key]
        override fun commit(values: Map<String, String>) { this.values.putAll(values) }
        override fun removePrefix(prefix: String) { values.keys.removeAll { it.startsWith(prefix) } }
    }

    private fun withResourceObservation(execution: AgentTeamMemberExecutionContext) = execution.copy(
        resourceObservation = AgentTeamResourceObservation.capture(execution,
            AgentTeamResourceObservation.Unit.PHONE_DISPATCH, 12, 0, 1_791_507_124_000, 1_200_000))

    private fun execution(goal: String, stage: CollaborationResearchStage = CollaborationResearchStage.VERIFY) =
        AgentTeamMemberExecutionContext(
            member = AgentTeamMember("provider", AgentDeliveryMode.RESPOND, role = "reviewer",
                objective = "Review the original evidence and propose a discriminating test.", instanceId = "node",
                context = mapOf("collaboration_group_id" to "group", "collaboration_name" to "Curie",
                    CollaborationResearchWorkflow.PERSON to "person-curie",
                    CollaborationGoalLoop.ENABLED to "1", CollaborationResearchWorkflow.STAGE to stage.name)),
            request = AgentRunRequest(conversationId = "group", messageId = "turn", taskId = "task",
                runId = "child", parentRunId = "root", goal = goal, idempotencyKey = "dispatch",
                context = mapOf(CollaborationGoalLoop.CRITERIA to "[]")),
            handoff = AgentSubagentContextHandoff("", emptyList(), 0, 0, false), depth = 0,
            provenance = AgentSubagentProvenance())

    private fun descriptor() = JSONObject().put("status", "ok").put("snapshot_id", "a".repeat(64))
        .put("goal_sha256", "b".repeat(64)).put("criteria_sha256", "c".repeat(64)).put("page_count", 25)
}
