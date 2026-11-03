package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationReviewMilestonesTest {
    private val candidate = "a".repeat(64)
    private val data = "b".repeat(64)
    private val authors = mapOf(candidate to "author", data to "peer")
    private fun item() = JSONObject().put("id", "review").put("member", "peer").put("stage", "VERIFY")
        .put("assignment", "Test the candidate against frozen independent observations")
        .put("depends_on", JSONArray()).put("independent_review", true).put("review_targets", JSONArray())
        .put("uses_milestones", JSONArray().put(candidate).put(data))
        .put("review_milestones", JSONArray().put(candidate))
    private fun compile(item: JSONObject) = CollaborationWorkGraph.compile(listOf(item), emptySet(), milestoneAuthors = authors)

    @Test fun typedInputsPreserveReviewerDataWithoutSelfReview() {
        val item = item()
        assertEquals("", compile(item).error)
        val context = CollaborationReviewTargets.context(item)
        assertEquals(setOf(candidate), CollaborationReviewTargets.milestones(CollaborationReviewTargets.restore(
            JSONObject(item.toString()).apply { remove("review_milestones"); remove("review_targets") }, context)))
        assertEquals(item.toString(), CollaborationReviewTargets.restore(JSONObject(item.toString()), context).toString())
    }

    @Test fun defaultStillReviewsEveryMilestoneAndRejectsSelfAuthoredSubjects() {
        assertTrue(compile(item().apply { remove("review_milestones") }).error.contains("different author"))
        assertTrue(compile(item().put("review_milestones", JSONArray().put(data))).error.contains("different author"))
    }

    @Test fun malformedUnknownEmptyAndDuplicatedTargetsAreRejected() {
        val bad = listOf<Any>("all", 1, JSONArray(), JSONArray().put("c".repeat(64)), JSONArray().put(candidate).put(candidate), JSONArray().put(12))
        bad.forEach { assertTrue(compile(item().put("review_milestones", it)).error.isNotBlank()) }
        assertTrue(compile(item().put("independent_review", false)).error.isNotBlank())
        val missing = item().put("uses_milestones", JSONArray().put(candidate).put(data).put("c".repeat(64)))
        assertTrue(compile(missing).error.contains("Unknown or ungranted"))
    }

    @Test fun supportingInputsCannotRemoveWholeAssignmentPrerequisites() {
        val producer = JSONObject().put("id", "solution").put("member", "author")
        val check = item().put("depends_on", JSONArray().put("solution")).put("review_targets", JSONArray().put("solution"))
            .put("uses_milestones", JSONArray().put(data)).put("review_milestones", JSONArray())
        val plan = CollaborationWorkGraph.compile(listOf(producer, check), emptySet(), milestoneAuthors = authors)
        assertEquals("", plan.error)
        assertEquals(setOf("solution"), CollaborationWorkGraph.dependencies(plan.work.single { it.getString("id") == "review" }))
    }

    @Test fun signaturesDistinguishFrozenInputsAndRolesButNotOrdering() {
        val original = item()
        val reordered = item().put("uses_milestones", JSONArray().put(data).put(candidate))
        assertEquals(CollaborationTeamOrganization.signature(original), CollaborationTeamOrganization.signature(reordered))
        assertNotEquals(CollaborationTeamOrganization.signature(original),
            CollaborationTeamOrganization.signature(item().put("review_milestones", JSONArray().put(data))))
        assertNotEquals(CollaborationTeamOrganization.signature(original),
            CollaborationTeamOrganization.signature(item().put("uses_milestones", JSONArray().put(candidate))))
    }
}
