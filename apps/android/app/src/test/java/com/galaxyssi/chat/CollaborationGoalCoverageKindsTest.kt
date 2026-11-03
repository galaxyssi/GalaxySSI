package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationGoalCoverageKindsTest {
    private class Case {
        val f = CollaborationGoalAcceptanceTest.Fixture(requirement = "Deliver a report",
            goal = "Deliver a report. Do not browse. This is an engineering check.", reviewKind = CollaborationReviewContract.KIND)
        val mapping = f.mappingBody()
        val review = f.coverageReviewBody(f.mapping)
        init {
            listOf("outcome", "constraint", "context").forEachIndexed { index, type ->
                listOf(mapping, review).forEach { body ->
                    body.getJSONArray("segments").getJSONObject(index).put("coverage_kind", type)
                        .put("criterion_ids", if (index == 0) JSONArray().put("document") else JSONArray())
                }
            }
        }
        fun validate() = CollaborationSemanticGoalCoverage.validate(mapping, review, JSONArray(f.prior), f.goal)
        fun reject() = assertThrows(IllegalArgumentException::class.java) { validate() }
    }

    @Test fun constraintsAndContextRemainCoveredWithoutBecomingNewProofTasks() {
        val c = Case()
        c.validate()
        assertEquals(1, JSONArray(c.f.prior).length())
        assertEquals(3, c.mapping.getJSONArray("segments").length())
        val mapping = c.f.publish(c.f.access.copy(nodeId = "typed-mapping", personId = "mapper", round = 2),
            c.f.item("typed", "artifact", JSONObject().put(CollaborationSemanticGoalCoverage.MAPPING, c.mapping)))
        c.review.put("target", mapping)
        val review = c.f.publish(c.f.access.copy(nodeId = "typed-review", personId = "peer", round = 3),
            c.f.item("typed-review", CollaborationReviewContract.KIND,
                JSONObject().put(CollaborationSemanticGoalCoverage.REVIEW, c.review)).put("parents", JSONArray().put(mapping)))
        val assessment = c.f.assessment().put("goal_coverage", JSONObject().put("mapping", mapping).put("review", review))
        val receipt = c.f.evaluate(assessment.toString(), c.f.access.copy(round = 4))
        assertTrue(receipt.feedback, receipt.accepted)
        assertTrue(receipt.feedback.contains("reviewer judgment"))
    }

    @Test fun outcomesAndUnclassifiedHistoryStillRequireCriterionLinks() {
        listOf(true, false).forEach { explicit ->
            val c = Case()
            val segment = c.mapping.getJSONArray("segments").getJSONObject(0)
            if (!explicit) segment.remove("coverage_kind")
            segment.put("criterion_ids", JSONArray())
            c.reject()
        }
    }

    @Test fun independentReviewerMustAgreeOnTheClassification() {
        val c = Case()
        c.review.getJSONArray("segments").getJSONObject(1).put("coverage_kind", "context")
        c.reject()
    }

    @Test fun restrictionsCannotBeOmittedOrReviewedAsUnknown() {
        val omitted = Case()
        omitted.mapping.getJSONArray("segments").remove(1)
        omitted.review.getJSONArray("segments").remove(1)
        omitted.reject()
        listOf("refuted", "not_tested").forEach { verdict ->
            val c = Case()
            c.review.put("verdict", verdict)
            c.review.getJSONArray("segments").getJSONObject(1).put("verdict", verdict)
            c.reject()
        }
    }

    @Test fun unknownKindsAndExtraFieldsAreRejected() {
        listOf("ignored", "", JSONObject.NULL, 1).forEach { type ->
            val c = Case()
            c.mapping.getJSONArray("segments").getJSONObject(1).put("coverage_kind", type)
            c.reject()
        }
        val c = Case()
        c.review.getJSONArray("segments").getJSONObject(1).put("permission_granted", true)
        c.reject()
    }

    @Test fun optionalConstraintLinksCannotNameUnknownOrDuplicateCriteria() {
        listOf(JSONArray().put("unknown"), JSONArray().put("document").put("document")).forEach { links ->
            val c = Case()
            c.mapping.getJSONArray("segments").getJSONObject(1).put("criterion_ids", links)
            c.reject()
        }
    }

    @Test fun classifyingSourcesDoesNotAllowDroppingEstablishedCriteria() {
        val c = Case()
        listOf(c.mapping, c.review).forEach { it.getJSONArray("segments").getJSONObject(0)
            .put("coverage_kind", "context").put("criterion_ids", JSONArray()) }
        c.reject()
        val assessment = c.f.assessment()
        assessment.getJSONArray("criteria").getJSONObject(0).put("requirement", "A weaker goal")
        assertFalse(c.f.evaluate(assessment.toString()).accepted)
    }

    @Test fun constraintLinksAloneCannotStandInForAnOutcome() {
        val c = Case()
        listOf(c.mapping, c.review).forEach { it.getJSONArray("segments").getJSONObject(0)
            .put("coverage_kind", "constraint") }
        c.reject()
    }

    @Test fun guidanceDoesNotConflateClassificationWithPermissionOrProof() {
        val prompt = CollaborationGoalLoop.instructions()
        assertTrue(prompt.contains("classification neither grants authority nor proves compliance"))
        assertTrue(prompt.contains("post-delivery task"))
        assertTrue(prompt.contains("not evidence of transport receipt"))
        assertTrue(prompt.contains("Reject a requested outcome misclassified"))
    }
}
