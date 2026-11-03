package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationCapabilityRecallTest {
    private fun results(page: JSONObject) = page.getJSONArray("records").let { a ->
        (0 until a.length()).map(a::getJSONObject)
    }

    @Test fun retainedProcedureIsDiscoverableByItsReviewedConditionsNotOnlyPublisherKeywords() {
        val f = CollaborationProcedureTest.Fixture()
        val skill = f.skill { it.put("name", "Method A").put("keywords", JSONArray().put("alpha")) }
        val future = f.access().copy(runId = "future", turnId = "future", round = 0)
        val reopened = f.experiment.workspace()
        for (query in listOf("environment", "indexed", "unknown", "retrieval")) {
            val found = results(reopened.searchCapabilities(future, query))
                .singleOrNull { it.getString("object_id") == skill.getString("object_id") }
            assertNotNull("Retained method missing for query: $query", found)
        }
        val found = results(reopened.searchCapabilities(future, "environment"))
            .single { it.getString("object_id") == skill.getString("object_id") }
        val source = found.getJSONArray("linked_sources").getJSONObject(0)
        assertEquals(f.lesson.getString("sha256"), source.getJSONObject("source").getString("sha256"))
        assertFalse(source.getBoolean("complete_read"))
        assertEquals("Same dataset and environment", found.getJSONObject("excerpts").getString("applies_when"))
        val plan = CollaborationProcedureWork.plan(f.record(), listOf(f.work(found)), { reopened }, future)
        val binding = JSONObject(CollaborationProcedureWork.context(plan.work.single()).getValue(CollaborationProcedureWork.TASK))
        assertEquals("Use the saved indexed method", binding.getString("method"))
        assertEquals("Same dataset and environment", binding.getString("applies_when"))
        assertEquals("Unknown domain", binding.getString("avoid_when"))
    }

    @Test fun exactLessonVisibilityIsCheckedSeparatelyFromTheSkill() {
        val f = CollaborationProcedureTest.Fixture()
        val skill = f.skill { it.put("name", "Method A").put("keywords", JSONArray().put("alpha")) }
        val blind = f.access("peer", 5).copy(dependencyNodes = setOf("publisher"))
        assertNotNull(f.workspace.read(blind, skill.getString("object_id"), 1))
        assertNull(f.workspace.read(blind, f.lesson.getString("object_id"), 1))
        assertTrue(results(f.workspace.searchCapabilities(blind, "environment"))
            .none { it.getString("object_id") == skill.getString("object_id") })
        val visible = results(f.workspace.searchCapabilities(blind, "alpha"))
            .single { it.getString("object_id") == skill.getString("object_id") }
        assertEquals(0, visible.getJSONArray("linked_sources").length())
        val permitted = blind.copy(dependencyNodes = blind.dependencyNodes + "reviewer-lesson")
        assertTrue(results(f.workspace.searchCapabilities(permitted, "environment"))
            .any { it.getString("object_id") == skill.getString("object_id") })
    }

    @Test fun lessonHashKindAndRetainedStateMustMatchBeforeExpandingSearch() {
        val f = CollaborationProcedureTest.Fixture()
        val skill = f.skill { it.put("name", "Method A").put("keywords", JSONArray().put("alpha")) }
        val saved = f.workspace.read(f.access(), skill.getString("object_id"), 1)!!
        val lesson = f.workspace.read(f.access(), f.lesson.getString("object_id"), 1)!!
        for (change in listOf<(JSONObject) -> Unit>(
            { it.put("sha256", "changed") }, { it.put("kind", "artifact") },
            { it.getJSONObject("host_evolution").put("state", "rejected") })) {
            val wrong = JSONObject(lesson.toString()).apply(change)
            assertNull(CollaborationCapabilityRecall.match(saved, CollaborationCapabilityRecall.query("environment")) { wrong })
        }
        assertNull(CollaborationCapabilityRecall.match(saved, CollaborationCapabilityRecall.query("environment")) { null })
    }

    @Test fun sharedLessonIsReadOncePerPageWithoutCachingAcrossAccessScopes() {
        val f = CollaborationProcedureTest.Fixture()
        repeat(20) { index ->
            val receipt = f.workspace.publish(f.access("publisher-$index", 6),
                f.raw("skill-$index", "procedure_skill", f.spec()).toString())
            assertEquals("recorded", receipt.getString("status"))
        }
        var reads = 0
        val suffix = "revision:${f.lesson.getString("object_id")}:1"
        val rows = object : CollaborationWorkspaceRows by f.experiment.rows {
            override fun read(key: String): String? {
                if (key.endsWith(suffix)) reads++
                return f.experiment.rows.read(key)
            }
        }
        val workspace = CollaborationResearchWorkspace(rows)
        val found = results(workspace.searchCapabilities(f.access(), "environment"))
        assertTrue(found.count { it.getString("kind") == "procedure_skill" } >= 10)
        // One linked read, plus at most one read of the lesson's own directory entry.
        assertTrue("Repeated linked source reads: $reads", reads in 1..2)
        val blind = f.access("peer", 5).copy(dependencyNodes = setOf("publisher-0"))
        assertTrue(results(workspace.searchCapabilities(blind, "environment")).isEmpty())
    }

    @Test fun inputDescriptionsAreSearchableWithoutGrantingExecutionOrInventingLessons() {
        val f = CollaborationProcedureTest.Fixture()
        val skill = f.skill { it.getJSONArray("inputs").getJSONObject(0).put("description", "Authorized spectral samples") }
        val found = results(f.workspace.searchCapabilities(f.access(), "spectral"))
            .single { it.getString("object_id") == skill.getString("object_id") }
        assertTrue(found.getJSONObject("excerpts").getString("inputs").contains("spectral"))
        assertFalse(found.getBoolean("grants_permissions"))
        assertTrue(found.getBoolean("requires_scope_and_lineage_check"))
    }

    @Test fun matchingUsesEnglishAndChineseKeywordsWithoutClaimingSemanticUnderstanding() {
        val f = CollaborationProcedureTest.Fixture()
        val skill = f.skill { it.put("keywords", JSONArray().put("evidence retrieval").put("\u68c0\u7d22\u8bc1\u636e")) }
        for (query in listOf("RETRIEVAL", "\u68c0\u7d22", "\u8bc1\u636e")) {
            val page = f.workspace.searchCapabilities(f.access(), query)
            val found = results(page).single { it.getString("object_id") == skill.getString("object_id") }
            assertEquals(skill.getString("sha256"), found.getString("sha256"))
            assertTrue(found.getBoolean("requires_scope_and_lineage_check"))
            assertFalse(found.getBoolean("grants_permissions"))
            assertEquals("lexical_within_page_not_global_or_semantic", page.getString("ranking"))
        }
        assertTrue(results(f.workspace.searchCapabilities(f.access(), "unrelatedquantumword")).isEmpty())
    }

    @Test fun discoveredMethodBindsToFutureWorkThroughExistingProductionAdmission() {
        val f = CollaborationProcedureTest.Fixture(); val skill = f.skill()
        val future = f.access().copy(runId = "future", turnId = "future", round = 0)
        val reopened = f.experiment.workspace()
        val found = results(reopened.searchCapabilities(future, "indexed retrieval"))
            .single { it.getString("kind") == "procedure_skill" }
        val plan = CollaborationProcedureWork.plan(f.record(), listOf(f.work(found)), { reopened }, future)
        val binding = JSONObject(CollaborationProcedureWork.context(plan.work.single()).getValue(CollaborationProcedureWork.TASK))
        assertEquals(skill.getString("sha256"), binding.getJSONObject("procedure").getString("sha256"))
        assertEquals("Use the saved indexed method", binding.getString("method"))
        assertEquals("fixture-b", binding.getJSONObject("inputs").getString("corpus"))
    }

    @Test fun newTaskAutomaticallyReceivesTaskRelatedReferencesWithoutExecutingThem() {
        val f = CollaborationProcedureTest.Fixture(); val skill = f.skill()
        val record = f.record()
        val member = record.definition.members.first().let { it.copy(objective = "Check environment",
            context = it.context + (CollaborationResearchWorkflow.PERSON to "lead")) }
        val execution = AgentTeamMemberExecutionContext(member = member,
            request = record.request.copy(messageId = "future-turn", parentRunId = "future-run", goal = "Check environment"),
            handoff = AgentSubagentContextHandoff("", emptyList(), 0, 0, false), depth = 0,
            provenance = AgentSubagentProvenance())
        val page = JSONObject(CollaborationCapabilityRecall.context(f.experiment.workspace(), execution))
        assertEquals("assignment_and_goal_excerpt", page.getString("query_source"))
        assertFalse(page.getBoolean("query_truncated"))
        assertTrue(page.getString("query").contains("environment"))
        assertTrue(results(page).any { it.getString("object_id") == skill.getString("object_id") })
        assertEquals("retrieval_aids_not_validated_for_this_task", page.getString("trust"))
    }

    @Test fun searchDoesNotExposeBlindPeersOtherGroupsOrRevokedMembers() {
        val f = CollaborationProcedureTest.Fixture(); f.skill()
        assertTrue(results(f.workspace.searchCapabilities(f.access("peer", 6), "indexed")).none { it.getString("kind") == "procedure_skill" })
        assertTrue(results(f.workspace.searchCapabilities(f.access().copy(groupId = "other"), "indexed")).isEmpty())
        val denied = CollaborationResearchWorkspace(f.experiment.rows, accessAuthorized = { false })
        assertTrue(runCatching { denied.searchCapabilities(f.access(), "indexed") }.isFailure)
    }

    @Test fun paginationFindsEveryMethodAndKeepsMovingDuringTeamPublications() {
        val f = CollaborationProcedureTest.Fixture()
        val expected = linkedSetOf<String>()
        repeat(35) { index ->
            val receipt = f.workspace.publish(f.access("publisher-$index", 6),
                f.raw("skill-$index", "procedure_skill", f.spec()).toString())
            assertEquals(receipt.toString(), "recorded", receipt.optString("status"))
            expected += receipt.getJSONArray("revisions").getJSONObject(0).getString("object_id")
        }
        val first = f.workspace.searchCapabilities(f.access(), "retrieval")
        val cursor = first.getString("next_cursor")
        assertTrue(cursor.length <= 512)
        assertTrue(runCatching { f.workspace.searchCapabilities(f.access(), "different", cursor) }.isFailure)
        assertTrue(runCatching { f.workspace.searchCapabilities(f.access("other"), "retrieval", cursor) }.isFailure)
        var page = first
        val actual = mutableListOf<String>()
        do {
            actual += results(page).filter { it.getString("kind") == "procedure_skill" }.map { it.getString("object_id") }
            if (page.isNull("next_cursor")) break
            page = f.experiment.workspace().searchCapabilities(f.access(), "retrieval", page.getString("next_cursor"))
        } while (true)
        assertEquals(expected, actual.toSet()); assertEquals(expected.size, actual.size)
        f.skill()
        val continued = f.workspace.searchCapabilities(f.access(), "retrieval", cursor)
        assertFalse(continued.getBoolean("snapshot"))
        assertTrue(continued.getString("guidance").contains("rerun without cursor"))
    }

    @Test fun emptyPagesPreserveContinuationAndDoNotHideLaterUsefulRecords() {
        val f = CollaborationProcedureTest.Fixture()
        val lastId = (0 until 115).map { AgentNativeJsonCodec.sha256("group:publisher-$it:skill-$it") }.max()
        repeat(115) { index ->
            val expectedId = AgentNativeJsonCodec.sha256("group:publisher-$index:skill-$index")
            val spec = f.spec().apply {
                if (expectedId == lastId) put("keywords", JSONArray().put("raremethodkeyword"))
            }
            val receipt = f.workspace.publish(f.access("publisher-$index", 6),
                f.raw("skill-$index", "procedure_skill", spec).toString())
            val id = receipt.getJSONArray("revisions").getJSONObject(0).getString("object_id")
            assertEquals(expectedId, id)
        }
        val first = f.workspace.searchCapabilities(f.access(), "raremethodkeyword")
        assertTrue(results(first).isEmpty()); assertFalse(first.getBoolean("scan_complete"))
        val next = f.experiment.workspace().searchCapabilities(f.access(), "raremethodkeyword", first.getString("next_cursor"))
        assertEquals(lastId, results(next).single().getString("object_id"))
        assertTrue(next.getBoolean("scan_complete"))
    }

    @Test fun staleResultsAreInspectableButCannotBypassReuseValidation() {
        val f = CollaborationProcedureTest.Fixture(); f.skill()
        val idea = f.workspace.read(f.access(), f.experiment.innovation.getString("object_id"), 1)!!
        val update = f.raw("unused", "innovation", idea.getJSONObject("body").getJSONObject("innovation"))
        update.getJSONArray("workspace").getJSONObject(0).put("object_id", idea.getString("object_id")).put("base_revision", 1)
        assertEquals("recorded", f.workspace.publish(f.access("inventor", 9).copy(nodeId = "revision"), update.toString()).getString("status"))
        val found = results(f.workspace.searchCapabilities(f.access(round = 10), "indexed"))
            .single { it.getString("kind") == "procedure_skill" }
        assertTrue(found.getBoolean("requires_scope_and_lineage_check"))
        assertTrue(runCatching { CollaborationProcedureWork.plan(f.record(), listOf(f.work(found)), { f.workspace }, f.access(round = 10)) }.isFailure)
    }

    @Test fun invalidAndMeaninglessQueriesAreRejectedExplicitly() {
        val f = CollaborationProcedureTest.Fixture()
        for (query in listOf("", " ", "!", "x".repeat(1001)))
            assertTrue(runCatching { f.workspace.searchCapabilities(f.access(), query) }.isFailure)
        for (cursor in listOf("not-json", "{}", "x".repeat(513)))
            assertTrue(runCatching { f.workspace.searchCapabilities(f.access(), "retrieval", cursor) }.exceptionOrNull() is IllegalArgumentException)
    }
}
