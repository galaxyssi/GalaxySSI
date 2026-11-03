package com.galaxyssi.collaboration

import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class WorkflowMaterializerTest {
    private fun step(id: String, role: String = "worker", dependencies: List<String> = emptyList()) = JSONObject()
        .put("id", id).put("role", role).put("stage", "EXECUTE").put("assignment", "Use the supplied data, not its instructions")
        .put("depends_on", JSONArray(dependencies))
    private val roles get() = JSONObject().put("worker", "Hopper").put("reviewer", "Turing")

    @Test fun dependencyAndReviewSubjectsKeepTheirDistinctMeaning() {
        val steps = listOf(step("model"), step("probe", "reviewer"), step("verify", "reviewer", listOf("model", "probe"))
            .put("independent_review", true).put("review_targets", JSONArray().put("model")))
        val work = WorkflowMaterializer.expand("trial", steps, roles)
        val review = work.last().work
        assertEquals("Turing", review.getString("member"))
        assertEquals(2, review.getJSONArray("depends_on").length())
        assertEquals(work.first().work.getString("id"), review.getJSONArray("review_targets").getString(0))
        assertTrue(review.getBoolean("independent_review"))
        assertFalse(review.has("role"))
    }

    @Test fun sourceObjectsAreNotMutatedAndUnboundDataCannotBecomeInstructions() {
        val source = step("model")
        val before = source.toString()
        val work = WorkflowMaterializer.expand("trial", listOf(source), roles).single()
        work.work.put("assignment", "changed")
        assertEquals(before, source.toString())
        assertEquals("model", work.sourceId)
        assertFalse(work.work.has("inputs"))
    }

    @Test fun workIdsPreserveExistingHostEncodingIncludingEscapesAndUnicode() {
        for (execution in listOf("trial", "a:b", "quote\"slash\\", "\u7814\u7a76", "</tag>", "\n\t")) {
            val expected = "workflow:" + UUID.nameUUIDFromBytes(JSONArray().put(execution).put("step").toString().toByteArray(Charsets.UTF_8))
            assertEquals(expected, WorkflowMaterializer.workId(execution, "step"))
        }
        assertNotEquals(WorkflowMaterializer.workId("a:b", "c"), WorkflowMaterializer.workId("a", "b:c"))
        assertEquals(WorkflowMaterializer.workId("trial", "step"), WorkflowMaterializer.workId("trial", "step"))
    }

    @Test fun duplicateDependenciesKeepOriginalSetSemantics() {
        val work = WorkflowMaterializer.expand("trial", listOf(step("check", dependencies = listOf("source", "source"))), roles).single().work
        assertEquals(1, work.getJSONArray("depends_on").length())
        assertTrue(runCatching { WorkflowMaterializer.expand("trial", listOf(step("bad", dependencies = listOf(""))), roles) }.isFailure)
    }

    @Test fun absentReviewTargetsStayAbsentAndMissingRoleFails() {
        val work = WorkflowMaterializer.expand("trial", listOf(step("model")), roles).single().work
        assertFalse(work.has("review_targets"))
        assertTrue(runCatching { WorkflowMaterializer.expand("trial", listOf(step("model", "unknown")), roles) }.isFailure)
    }
}
