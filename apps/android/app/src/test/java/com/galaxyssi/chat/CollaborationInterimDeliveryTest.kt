package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationInterimDeliveryTest {
    private fun fixture(reviewer: String = "reviewer") =
        CollaborationGoalAcceptanceTest.Fixture(reviewer = reviewer, reviewKind = CollaborationReviewContract.KIND)
    private fun proposal(f: CollaborationGoalAcceptanceTest.Fixture) = f.assessment().put("decision", "continue")
        .put(CollaborationInterimDelivery.FIELD, JSONObject().put("criterion_id", "document").put("target", f.delivery))
        .also { it.getJSONArray("criteria").getJSONObject(0).put("status", "open") }
    private fun deliver(f: CollaborationGoalAcceptanceTest.Fixture, raw: JSONObject = proposal(f)): JSONObject =
        f.engine.deliverInterim(f.access.copy(round = 4), raw.toString(), f.prior) { ref, saved ->
            JSONObject().put("target", ref).put("text", saved.getJSONObject("body").getString("content"))
        }
    private fun verdict(value: String) = JSONObject().put("verdict", value).put("rationale", "Fixture: distinguish content from later acknowledgement")
        .put("unresolved", JSONArray().apply { if (value != "supported") put("A condition remains unobserved") })
    private fun partialReview(f: CollaborationGoalAcceptanceTest.Fixture, ready: String = "supported"): JSONObject {
        val body = JSONObject(f.workspace.read(f.reviewAccess, f.review.getString("object_id"), 1)!!.getJSONObject("body").toString())
        body.getJSONObject(CollaborationReviewContract.KIND).put("verdict", "not_tested")
            .put("unresolved", JSONArray().put("User acknowledgement remains unobserved"))
            .put(CollaborationInterimDelivery.READINESS, verdict(ready))
        return f.publish(f.reviewAccess.copy(round = 3, nodeId = "readiness-revision"), f.item("unused", CollaborationReviewContract.KIND, body)
            .put("object_id", f.review.getString("object_id")).put("base_revision", 1).put("parents", JSONArray().put(f.delivery)))
    }

    @Test fun reviewedInterimContentCanPrecedeGoalCompletion() {
        val f = fixture(); val raw = proposal(f)
        assertEquals("Comparison with explicit limits", deliver(f, raw).getString("text"))
        assertEquals("open", raw.getJSONArray("criteria").getJSONObject(0).getString("status"))
        assertFalse(f.evaluate(raw.toString()).accepted)
        assertEquals("continue", CollaborationGoalLoop.disposition(raw.toString(), f.prior, acceptanceVerified = true))
    }

    @Test fun separateContentVerdictDoesNotEraseUnmetPostconditions() {
        val f = fixture(); val review = partialReview(f)
        val raw = proposal(f)
        raw.getJSONArray("criteria").getJSONObject(0).put("review", review)
        assertTrue(deliver(f, raw).has("text"))
        raw.remove(CollaborationInterimDelivery.FIELD)
        raw.put("decision", "achieved").getJSONArray("criteria").getJSONObject(0).put("status", "met")
        assertFalse(f.evaluate(raw.toString(), who = f.access.copy(round = 4)).accepted)
        val preserved = f.workspace.read(f.reviewAccess.copy(round = 4), review.getString("object_id"), review.getInt("revision"))!!
        assertEquals("not_tested", preserved.getJSONObject("body").getJSONObject(CollaborationReviewContract.KIND).getString("verdict"))
    }

    @Test fun negativeContentSelfReviewAndMissingSeparateReadinessCannotRelease() {
        for (ready in listOf("not_tested", "refuted")) {
            val f = fixture(); val raw = proposal(f)
            raw.getJSONArray("criteria").getJSONObject(0).put("review", partialReview(f, ready))
            assertThrows(IllegalArgumentException::class.java) { deliver(f, raw) }
        }
        assertThrows(IllegalArgumentException::class.java) { deliver(fixture("author")) }
        assertThrows(IllegalArgumentException::class.java) { CollaborationInterimDelivery.readiness(verdict("not_tested")) }
    }

    @Test fun anotherCurrentNegativeContentReviewCannotBeOmitted() {
        val f = fixture()
        val check = JSONObject().put("criterion_id", "document").put("requirement", f.criterion.getString("requirement"))
            .put("target", f.delivery).put("verdict", "refuted").put("rationale", "The content itself has a contradiction")
            .put("unresolved", JSONArray().put("contradiction")).put(CollaborationInterimDelivery.READINESS, verdict("refuted"))
        f.publish(f.reviewAccess.copy(personId = "second", nodeId = "second-review"),
            f.item("dissent", CollaborationReviewContract.KIND, JSONObject().put(CollaborationReviewContract.KIND, check))
                .put("parents", JSONArray().put(f.delivery)))
        assertThrows(IllegalArgumentException::class.java) { deliver(f) }
    }

    @Test fun interimCannotChangeTheOriginalContractOrTargetOrUseUnestablishedCriteria() {
        val f = fixture()
        val changed = proposal(f)
        changed.getJSONArray("criteria").getJSONObject(0).put("requirement", "Easier goal")
        assertThrows(IllegalArgumentException::class.java) { deliver(f, changed) }
        val wrong = proposal(f)
        wrong.getJSONObject(CollaborationInterimDelivery.FIELD).put("target", JSONObject(f.delivery.toString()).put("sha256", "0".repeat(64)))
        assertThrows(IllegalArgumentException::class.java) { deliver(f, wrong) }
        assertThrows(IllegalArgumentException::class.java) { CollaborationInterimDelivery.criterion(proposal(f), JSONArray()) }
        f.authorized = false
        assertNotNull(runCatching { deliver(f) }.exceptionOrNull())
    }

    @Test fun staleAndUnreadEvidenceCannotBeReleasedAsReviewedContent() {
        val f = fixture()
        f.publish(f.access.copy(nodeId = "update", personId = "author", round = 2),
            f.item("new", "artifact", JSONObject().put("content", "Changed"))
                .put("object_id", f.delivery.getString("object_id")).put("base_revision", 1))
        assertThrows(IllegalArgumentException::class.java) { deliver(f) }
        val unread = CollaborationGoalAcceptanceTest.Fixture(reviewKind = CollaborationReviewContract.KIND,
            tool = "fixture", reviewCitesOriginal = true, reviewReadsOriginal = false)
        assertNotNull(runCatching { deliver(unread) }.exceptionOrNull())
    }

    @Test fun failureAnalysisMayCiteFailedObservationsWithoutCertifyingGoalAcceptance() {
        val f = CollaborationGoalAcceptanceTest.Fixture(reviewKind = CollaborationReviewContract.KIND, tool = "fixture",
            output = "{\"success\":false,\"status\":\"failed\"}", reviewCitesOriginal = true)
        assertTrue(deliver(f).has("text"))
        assertFalse(f.evaluate().accepted)
    }

    @Test fun invalidInterimAndContradictoryReviewsHaveExplicitValidationFailures() {
        val f = fixture()
        for (bad in listOf(JSONObject.NULL, "invented", JSONObject().put("criterion_id", "document"))) {
            val result = CollaborationAssessmentValidation.inspect(proposal(f).put(CollaborationInterimDelivery.FIELD, bad).toString())
            assertEquals("$.interim_delivery", result.failure!!.path)
            assertTrue(result.syntaxValid)
        }
        assertNull(CollaborationGoalLoop.decode(proposal(f).put("decision", "achieved").toString()))
        val review = f.workspace.read(f.reviewAccess, f.review.getString("object_id"), 1)!!.getJSONObject("body")
        review.getJSONObject(CollaborationReviewContract.KIND).put(CollaborationInterimDelivery.READINESS, verdict("not_tested"))
        assertThrows(IllegalArgumentException::class.java) { CollaborationReviewContract.validate(CollaborationReviewContract.KIND, review) }
    }
}
