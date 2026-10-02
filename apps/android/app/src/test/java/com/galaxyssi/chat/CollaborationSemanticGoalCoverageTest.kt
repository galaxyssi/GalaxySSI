package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationSemanticGoalCoverageTest {
    private fun fixture() = CollaborationGoalAcceptanceTest.Fixture()

    private fun rejected(change: (JSONObject, JSONObject, JSONArray) -> Unit) {
        val f = fixture()
        val mapping = f.mappingBody()
        val review = f.coverageReviewBody(f.mapping)
        val criteria = JSONArray(f.prior)
        change(mapping, review, criteria)
        assertThrows(IllegalArgumentException::class.java) {
            CollaborationSemanticGoalCoverage.validate(mapping, review, criteria, f.goal)
        }
    }

    @Test fun missingCoverageAndInlineSelfCertificationCannotAccept() {
        val f = fixture()
        val absent = f.assessment().apply { remove("goal_coverage") }
        val receipt = f.evaluate(absent.toString())
        assertFalse(receipt.accepted)
        assertTrue(receipt.feedback.contains("goal_coverage"))
        absent.put("goal_coverage", JSONObject().put("mapping", f.mappingBody()).put("review", f.coverageReviewBody(f.mapping)))
        assertFalse(f.evaluate(absent.toString()).accepted)
    }

    @Test fun supportedCoverageIsExplicitlyAReviewerJudgmentNotScientificTruth() {
        val f = fixture()
        val receipt = f.evaluate()
        assertTrue(receipt.feedback, receipt.accepted)
        assertTrue(receipt.feedback.contains("reviewer judgment"))
        assertTrue(receipt.feedback.contains("not objective scientific truth"))
        assertTrue(receipt.feedback.contains("not empirical"))
    }

    @Test fun hostSourceIsStableLosslessAndDoesNotSplitUnicodeCodePoints() {
        listOf("  A;\r\n B.  \n", "A\uD83D\uDE00B", "a".repeat(1023) + "\uD83D\uDE00" + "b".repeat(2048),
            " ".repeat(5000) + "Final constraint", "Value 3.14; do not run.\n").forEach { goal ->
            val source = CollaborationSemanticGoalCoverage.source(goal)
            assertEquals(source.toString(), CollaborationSemanticGoalCoverage.source(goal).toString())
            val segments = source.getJSONArray("segments")
            val texts = (0 until segments.length()).map { index ->
                assertEquals("source-${index + 1}", segments.getJSONObject(index).getString("id"))
                segments.getJSONObject(index).getString("text")
            }
            assertEquals(goal, texts.joinToString(""))
            assertTrue(texts.none { it.last().isHighSurrogate() || it.first().isLowSurrogate() })
        }
        assertEquals("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", // SHA-256 of raw UTF-8 "abc".
            CollaborationSemanticGoalCoverage.source("abc").getString("goal_sha256"))
    }

    @Test fun goalHashCannotBeReplacedAndModelsDoNotSupplySourceTextOrOffsets() {
        listOf("", "0".repeat(64), CollaborationSemanticGoalCoverage.source("Deliver a comparison").getString("goal_sha256")).forEach { hash ->
            rejected { mapping, _, _ -> mapping.put("goal_sha256", hash) }
        }
        rejected { mapping, _, _ -> mapping.put("original_goal", fixture().goal) }
        listOf("start", "end", "text").forEach { key ->
            rejected { mapping, _, _ -> mapping.getJSONArray("segments").getJSONObject(0).put(key, "model replacement") }
        }
        rejected { mapping, _, _ -> mapping.getJSONArray("segments").getJSONObject(0).put("id", "invented-source") }
    }

    @Test fun allCriteriaAndTheirVerificationConstraintsMustBeBound() {
        listOf("id", "requirement", "verification").forEach { field ->
            rejected { _, _, criteria -> criteria.getJSONObject(0).put(field, "substituted") }
        }
        rejected { _, _, criteria -> criteria.getJSONObject(0)
            .put("required_observations", JSONArray().put(JSONObject().put("origin", "android_cloud_tool").put("tool", "different"))) }
        rejected { _, _, criteria -> criteria.put(criteria.getJSONObject(0)) }
        rejected { mapping, _, criteria ->
            val extra = JSONObject(criteria.getJSONObject(0).toString()).put("id", "unmapped")
            criteria.put(extra)
            mapping.put("criteria_sha256", CollaborationSemanticGoalCoverage.criteriaHash(criteria))
        }
    }

    @Test fun criterionBindingIsOrderStableButCoversValidatorInputsAndSourceRequirements() {
        val f = fixture()
        val criteria = JSONArray(f.prior)
        val hash = CollaborationSemanticGoalCoverage.criteriaHash(criteria)
        criteria.getJSONObject(0).put("status", "met").put("evidence", JSONArray().put("new receipt"))
        assertEquals(hash, CollaborationSemanticGoalCoverage.criteriaHash(criteria))
        val second = JSONObject(criteria.getJSONObject(0).toString()).put("id", "other")
        val forward = JSONArray().put(criteria.getJSONObject(0)).put(second)
        val reverse = JSONArray().put(second).put(criteria.getJSONObject(0))
        assertEquals(CollaborationSemanticGoalCoverage.criteriaHash(forward), CollaborationSemanticGoalCoverage.criteriaHash(reverse))
        val spec = JSONObject().put("id", "exact_integer_sum.v1").put("operands", JSONArray().put("2").put("3"))
        criteria.getJSONObject(0).put("validator", spec)
        val qualifiedHash = CollaborationSemanticGoalCoverage.criteriaHash(criteria)
        assertNotEquals(hash, qualifiedHash)
        spec.put("operands", JSONArray().put("1").put("4"))
        assertNotEquals(qualifiedHash, CollaborationSemanticGoalCoverage.criteriaHash(criteria))
    }

    @Test fun fullMultiSegmentCoveragePassesButReviewedOmissionStillFailsHostGate() {
        val f = CollaborationGoalAcceptanceTest.Fixture(requirement = "Deliver a comparison; do not run experiments.")
        val mapping = f.mappingBody()
        val review = f.coverageReviewBody(f.mapping)
        assertEquals(2, mapping.getJSONArray("segments").length())
        CollaborationSemanticGoalCoverage.validate(mapping, review, JSONArray(f.prior), f.goal)

        val omitted = f.mappingBody()
        omitted.put("segments", JSONArray().put(omitted.getJSONArray("segments").getJSONObject(0)))
        val saved = f.publish(f.access.copy(nodeId = "omitted-mapping", personId = "mapper"),
            f.item("omitted-mapping", "artifact", JSONObject().put(CollaborationSemanticGoalCoverage.MAPPING, omitted)))
        val savedReview = f.publish(f.access.copy(nodeId = "omitted-review", personId = "coverage-reviewer", round = 4),
            f.item("omitted-review", CollaborationReviewContract.KIND,
                JSONObject().put(CollaborationSemanticGoalCoverage.REVIEW, f.coverageReviewBody(saved)))
                .put("parents", JSONArray().put(saved)))
        val report = f.assessment().put("goal_coverage", JSONObject().put("mapping", saved).put("review", savedReview))
        val receipt = f.evaluate(report.toString(), who = f.access.copy(round = 5))
        assertFalse(receipt.accepted)
        assertTrue(receipt.feedback, receipt.feedback.contains("all host source IDs"))
    }

    @Test fun unknownDuplicateOrEmptyCriterionLinksCannotPass() {
        listOf(JSONArray(), JSONArray().put("unknown"), JSONArray().put("document").put("document"), JSONArray().put(1)).forEach { ids ->
            rejected { mapping, _, _ -> mapping.getJSONArray("segments").getJSONObject(0).put("criterion_ids", ids) }
        }
        rejected { _, review, _ -> review.getJSONArray("segments").getJSONObject(0).put("criterion_ids", JSONArray().put("different")) }
    }

    @Test fun everySourceSegmentNeedsAnUnambiguousIndependentVerdict() {
        rejected { _, review, _ -> review.put("segments", JSONArray()) }
        rejected { _, review, _ -> review.getJSONArray("segments").put(review.getJSONArray("segments").getJSONObject(0)) }
        rejected { _, review, _ -> review.getJSONArray("segments").getJSONObject(0).put("id", "unmapped") }
        rejected { _, review, _ -> review.put("unresolved", JSONArray().put("A constraint was omitted")) }
        rejected { _, review, _ -> review.getJSONArray("segments").getJSONObject(0).put("verdict", "not_tested") }
        rejected { _, review, _ -> review.getJSONArray("segments").getJSONObject(0).put("unresolved", JSONArray().put("Not checked")) }
        rejected { _, review, _ -> review.getJSONArray("segments").getJSONObject(0).put("rationale", " ") }
    }

    @Test fun mappingAuthorCannotReviewCoverageEvenFromAnotherDispatch() {
        val f = CollaborationGoalAcceptanceTest.Fixture(coverageReviewer = "mapper")
        assertFalse(f.evaluate().accepted)
    }

    @Test fun coordinatorAuthorAndOnePeerCanCompleteWithoutAThirdPerson() {
        val f = CollaborationGoalAcceptanceTest.Fixture(deliveryAuthor = "lead", mappingAuthor = "lead",
            reviewer = "peer", coverageReviewer = "peer")
        val people = listOf(f.delivery, f.mapping, f.review, f.coverageReview).map { ref ->
            f.workspace.read(f.access, ref.getString("object_id"), ref.getInt("revision"))!!.getString("person_id")
        }.toSet()
        assertEquals(setOf("lead", "peer"), people)
        assertTrue(f.evaluate().feedback, f.evaluate().accepted)
    }

    @Test fun evaluatingCoordinatorCannotSelfCertifyItsCriterionDecomposition() {
        val f = CollaborationGoalAcceptanceTest.Fixture(coverageReviewer = "lead")
        val receipt = f.evaluate()
        assertFalse(receipt.accepted)
        assertTrue(receipt.feedback.contains("coordinator"))
        val independent = fixture()
        assertFalse(independent.evaluate(who = independent.access.copy(personId = "")).accepted)
    }

    @Test fun previousMappingContributorCannotBecomeIndependentByChangingLatestAuthor() {
        val f = fixture()
        val mapping = f.publish(f.access.copy(nodeId = "mapping-revision", personId = "editor"),
            f.item("unused", "artifact", JSONObject().put(CollaborationSemanticGoalCoverage.MAPPING, f.mappingBody()))
                .put("object_id", f.mapping.getString("object_id")).put("base_revision", 1))
        val review = f.publish(f.access.copy(nodeId = "mapper-review", personId = "mapper", round = 4),
            f.item("new-coverage-review", CollaborationReviewContract.KIND,
                JSONObject().put(CollaborationSemanticGoalCoverage.REVIEW, f.coverageReviewBody(mapping)))
                .put("parents", JSONArray().put(mapping)))
        val report = f.assessment().put("goal_coverage", JSONObject().put("mapping", mapping).put("review", review))
        val receipt = f.evaluate(report.toString(), who = f.access.copy(round = 5))
        assertFalse(receipt.accepted)
        assertTrue(receipt.feedback.contains("previous contributor"))
    }

    @Test fun staleAndForgedCoverageReferencesCannotPass() {
        listOf("mapping", "review").forEach { field ->
            val f = fixture()
            val report = f.assessment()
            report.getJSONObject("goal_coverage").getJSONObject(field).put("sha256", "0".repeat(64))
            val receipt = f.evaluate(report.toString(), who = f.access.copy(round = 4))
            assertFalse(receipt.accepted)
            assertTrue(receipt.feedback, receipt.feedback.contains("digest"))
        }
        val f = fixture()
        f.publish(f.access.copy(nodeId = "mapping-update", personId = "mapper"),
            f.item("unused", "artifact", JSONObject().put(CollaborationSemanticGoalCoverage.MAPPING, f.mappingBody()))
                .put("object_id", f.mapping.getString("object_id")).put("base_revision", 1))
        assertFalse(f.evaluate().accepted)
    }

    @Test fun missingParentsOrWrongMappingTargetCannotPassHostAcceptance() {
        listOf(false, true).forEach { wrongTarget ->
            val f = fixture()
            val check = f.coverageReviewBody(if (wrongTarget) f.delivery else f.mapping)
            val item = f.item("other-review", CollaborationReviewContract.KIND,
                JSONObject().put(CollaborationSemanticGoalCoverage.REVIEW, check))
            if (wrongTarget) item.put("parents", JSONArray().put(f.mapping))
            val review = f.publish(f.access.copy(nodeId = "other-review-node", personId = "another-reviewer"), item)
            val report = f.assessment().put("goal_coverage", JSONObject().put("mapping", f.mapping).put("review", review))
            val receipt = f.evaluate(report.toString(), who = f.access.copy(round = 4))
            assertFalse(receipt.accepted)
            assertTrue(receipt.feedback, receipt.feedback.contains(if (wrongTarget) "different delivery" else "preserved delivery reference"))
        }
    }

    @Test fun savedMappingTamperingAndHistoricalReuseAreRejected() {
        val f = fixture()
        val key = f.rows.data.keys.single { it.contains("revision:${f.mapping.getString("object_id")}:1") }
        val saved = JSONObject(f.rows.data.getValue(key))
        saved.getJSONObject("body").getJSONObject(CollaborationSemanticGoalCoverage.MAPPING).put("goal_sha256", "0".repeat(64))
        f.rows.data[key] = saved.toString()
        assertFalse(f.evaluate().accepted)
        val historical = fixture()
        assertFalse(historical.evaluate(who = historical.access.copy(turnId = "later", runId = "later")).accepted)
    }
}
